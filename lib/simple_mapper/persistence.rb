require File.expand_path(File.dirname(__FILE__) + '/support')
module SimpleMapper
  module Persistence
    # TODO: Write in inheritability for models. Should this instead be a place that plugins can plug in a callback?
    def self.prepare_for_inheritance(klass)
    end

    def self.included(klass)
      klass.extend ClassMethods
      require File.expand_path(File.dirname(__FILE__) + '/plugin_support')
      klass.send(:include, SimpleMapper::PluginSupport)
    end

    module ClassMethods
      attr_reader :format
      def debug?; @debug end
      def debug!; @debug = true end

      def connection_adapters
        @connection_adapters ||= Hash.new {|h,k| h[k] = {}}
      end

      def add_connection_adapter(name_or_adapter,adapter=nil,&block)
        if adapter.nil?
          adapter = name_or_adapter
          name = :default
        else
          name = name_or_adapter.to_sym
        end
        # Should complain if the adapter doesn't exist.
        connection_adapters[name][:adapter] = adapter
        require "#{File.dirname(__FILE__)}/adapters/#{adapter}_adapter"
        connection_adapters[name][:init_block] = block if block_given?
        connection_adapters[name][:debug] = @debug
        [name, adapter]
      end

      # This is only here to show you in the docs how to clone a connection
      #   connection_adapters[adapter_name] = connection_adapters[adapter_name]
      #   connections[adapter_name] = klass.connection(adapter_name)
      def clone_connection(klass,adapter_name=nil)
        raise 'Not Implemented!'
      end

      # set_format :xml
      # self.format = :json
      def format=(format)
        @format_name = format.to_s
        require "#{File.dirname(__FILE__)}/formats/#{@format_name}_format"
        @format = Object.module_eval("::SimpleMapper::#{@format_name.camelize}Format", __FILE__, __LINE__)
        include @format
      end
      alias :set_format :format=
      attr_reader :format_name

      def entity_name
        @entity_name ||= name
      end
      attr_writer :entity_name
      alias :set_entity_name :entity_name=

      def connections
        @connections ||= {}
      end
      def connection(name=:default,refresh=false)
        connections[name] = begin
          # Initialize the connection with the connection adapter.
          raise ArgumentError, "Must include :adapter!" unless connection_adapters[name][:adapter].to_s.camelize.length > 0
          adapter = Object.module_eval("::SimpleMapper::#{connection_adapters[name][:adapter].to_s.camelize}Adapter", __FILE__, __LINE__).new
          connection_adapters[name][:init_block].in_context(adapter).call if connection_adapters[name][:init_block].is_a?(Proc)
          adapter.set_headers format.mime_type_headers
          adapter.debug! if connection_adapters[name][:debug]
          adapter
        end if !connections[name] || refresh
        connections[name]
      end

      # get
      # Works with pagination, provided the last object in the returned array responds to .meta and that meta information
      # includes a total and a url for the next page of results.
      def get(*args)
        adapter = adapter_from_args(*args)
        objs = extract_from(connection(adapter || :default).get(*args))
        # puts "#{objs ? objs.length : 0} objects."
        # puts "Like #{objs[0].inspect}" if objs
        if objs.is_a?(Array)
          safe = 1
          while(objs[-1].respond_to?(:meta) && objs[-1].meta['total'] > objs.length && objs[-1].meta['next'])
            safe += 1
            objs.concat(extract_from(connection(adapter || :default).raw_get(objs[-1].meta['next'])))
            break if safe >= 50 # Safeguard: if we do 50 requests we're probably on a runaway. Paginating at 50/page would be 2500 records...
          end
          objs.each {|e| e.instance_variable_set(:@adapter, adapter)} if adapter
        else
          objs.instance_variable_set(:@adapter, adapter) if adapter
        end
        # puts "TOTAL #{objs ? objs.length : 0} objects in all."
        # puts "Like #{objs[-1].inspect}" if objs
        objs
      end

      def get_from_url(url, adapter=:default)
        objs = extract_from(connection(adapter).raw_get(url))
        if objs.is_a?(Array)
          safe = 1
          while(objs[-1].respond_to?(:meta) && objs[-1].meta['total'] > objs.length && objs[-1].meta['next'])
            safe += 1
            objs.concat(extract_from(connection(adapter || :default).raw_get(objs[-1].meta['next'])))
            break if safe >= 50 # Safeguard: if we do 50 requests we're probably on a runaway. Paginating at 50/page would be 2500 records...
          end
          objs.each {|e| e.instance_variable_set(:@adapter, adapter)} if adapter
        else
          objs.instance_variable_set(:@adapter, adapter) if adapter
        end
        objs
      end

      # new.save
      def create(*args)
        new(*args).save
      end

      def persistent?
        true
      end

      def extract_from(formatted_data)
        objs = send(:"from_#{format_name}", formatted_data)
        objs.is_a?(Array) ? objs.collect {|e| e.extended {@persisted = true}} : objs.extended {@persisted = true}
      end

      def extract_one(formatted_data, identifier=nil)
        objs = extract_from(formatted_data)
        if objs.is_a?(Array)
          identifier.nil? ? objs.first : objs.reject {|e| e.identifier != identifier}[0]
        else
          identifier.nil? ? objs : (objs.identifier == identifier ? objs : nil)
        end
      end

      def load(data=nil)
        obj = allocate
        obj.send(:initialize, data)
        obj.original_data = data
        obj
      end

      private
        def adapter_from_args(*args)
          adapter = nil
          adapter = args.first.delete(:adapter) if args.first.is_a?(Hash)
          adapter
        end
    end

    def initialize(data=nil)
      self.data = data unless data.nil?
    end
    attr_reader :identifier

    def original_data=(data)
      @original_data = data.freeze
      @original_attributes = data.keys
    end
    attr_reader :original_data
    attr_reader :original_attributes

    # Reads the data from the object for saving back to the persisted store. This is provided as a default
    # method, but you can overwrite it in your model.
    def formatted_data
      send("to_#{self.class.format_name}".to_sym)
    end

    def dirty?
      data != original_data
    end

    # persisted? ? put : post
    def save
      persisted? ? put : post
    end

    # sends a put request with self.data
    def put(*args)
      new_rec = self.class.extract_one(self.class.connection(@adapter || :default).put(identifier, formatted_data, *args), identifier)
      raise "Request did not return an object" if new_rec.nil?
      self.data = new_rec.to_hash
      self
    end

    # sends a post request with self.data
    def post(*args)
      new_rec = self.class.extract_one(self.class.connection(@adapter || :default).post(formatted_data, *args))
      raise "Request did not return an object" if new_rec.nil?
      self.data = new_rec.to_hash
      @persisted = true
      self
    end

    # delete
    def delete
      if self.class.connection(@adapter || :default).delete(identifier)
        @persisted = false
        instance_variable_set('@'+self.class.identifier, nil)
        true
      else
        false
      end
    end

    def persisted?
      !!@persisted && !self.class.identifier.nil? && !self.send(self.class.identifier).nil?
    end
  end
end
