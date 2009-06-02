require File.expand_path(File.dirname(__FILE__) + '/../support/inflector')

module SimpleMapper
  module Associations
    # Returns an Association::Instance or Association::Set object (depending on the type of association, :single or :many),
    # with the association applied to the current object. Note that the association definition object is duplicated when it
    # is applied to an object -- this allows for them to be modified _after_ they are applied to an object without modifying
    # the class association template.
    def association_set(name,options={})
      @association_sets ||= {}
      names = name.is_a?(Array) ? name : [name]
      @association_sets[names.flatten.sort.join('&')] ||= names.inject(associations[names.shift]) {|a,n| a.merge(n)}.set(self)
    end

    # Accesses name in assocations hash
    def association(name)
      associations[name]
    end

    # Generates (and caches) a hash of the associations for this object's class -- but duplicates that are applied to this object.
    def associations
      @associations || begin
        @associations = {}
        self.class.associations.keys.each {|k| @associations[k] = self.class.associations[k].apply_to(self)}
        obj = self
        (class << @associations; self end).send(:define_method, :[]) do |k|
          obj.class.associations[k].apply_to(obj)
        end
      end
      @associations
    end

    def self.included(base)
      base.extend(AssociationMacros)
    end

    # AssociationMacros
    # 
    # This class is automatically extended into your model class when you include SimpleMapper::Associations, and therefore
    # gives all its methods to your model class.
    # 
    # There are currently only two types of associations: :single and :many. These can be customized by applying
    # primary or foreign association options (see Association). Different from ActiveRecord or DataMapper,
    # these methods ONLY define an association mapping between models, they don't rely on an accessor method.
    # By default, association accessor methods are created, but this can be disabled by specifying :accessor => false,
    # or simply by overwriting the accessor method after creating the association.
    # For :single type associations, a setter method is created, of the style 'association='. For example, if a
    # Person.has_many :pets, then a pet would by default have a person= method.
    # 
    # These macros are the only place that assume a method 'key' in your model class in order to automatically assume
    # assocation attributes. For example, if a Door.has_many :doorknobs and Door.key == :id, then Doorknob will be
    # assumed to have methods 'door_id' and 'door_id='. To change that up a little, if a Door.has_many(:doorknobs).as(:owner) and
    # Door.key == :name, then Doorknob will be assumed to have methods 'owner_name' and 'owner_name='.
    # 
    # See Association for more information on assumptions that are made about your model class.
    module AssociationMacros
      def associations
        @associations ||= {}
      end
      def association(name, type, options={})
        accessor = options.has_key?(:accessor) ? options.delete(:accessor) : true
        raise ArgumentError, "type must be :single or :many" unless [:single, :many].include?(type)
        associations[name] = Association.new(self, type, {:class_name => name}.merge(options))
        define_method(name.to_s+'=') do |object|
          association_set(name).associate(object)
        end if type == :single
        define_method(name) do
          association_set(name)
        end if accessor
        associations[name]
      end

      def has_one(name, options={})
        assoc = association(name, :single, options)
        assoc.dynamic {|assoc,obj| assoc.foreign(Inflector.underscore(assoc.act_as.to_s) + '_' + self.key.to_s => self.key) if assoc.act_as} unless self.name.underscore == assoc.instance_variable_get(:@options)[:class_name].to_s
        assoc
      end

      def belongs_to(name, options={})
        assoc = association(name, :single, options)
        assoc.dynamic {|assoc,obj| assoc.primary(assoc.associated_klass.key => Inflector.underscore(name.to_s) + '_' + assoc.associated_klass.key.to_s)} unless self.name.underscore == assoc.instance_variable_get(:@options)[:class_name].to_s
        assoc
      end

      def has_many(name, options={})
        assoc = association(name, :many, {:class_name => Inflector.singularize(name)}.merge(options))
        assoc.dynamic {|assoc,obj| assoc.foreign(Inflector.underscore(assoc.act_as.to_s) + '_' + self.key.to_s => self.key) if assoc.act_as} unless self.name.underscore == assoc.instance_variable_get(:@options)[:class_name].to_s
        assoc
      end
    end

    # Association is a completely independent class that is designed to use standard methods in your model
    # in order to bring associations to that model class. The following assumptions are made about the logic
    # of the concept of associations:
    # 
    # 1. object -> associated_objects: associations are ALWAYS managed on a basis of one object being associated with other objects. This means that you can specify association attributes that are based on the primary object, the associated (foreign) object, or both; but you can only 'scope' the finding of associated objects based on foreign attributes.
    # 2. primary, foreign, and scope: primary refers to the object in hand, foreign refers to an associated object, and scope refers to a subset of the associated objects. Primary options govern the association-related attributes on the primary object, Foreign options govern the association-related attributes on the foreign object, and Scope options are simply extra unrelated attributes used to find a smaller group within the otherwise associatable objects.
    # 3. Model.all: the 'all' method is called on your Model in order to find associated records, and is passed the aggregated finder_options.
    # 
    # Todo: Add in the amazing :through option
    class Association
      OPTIONS = [:class_name]

      attr_reader :type
      
      def initialize(klass, type, options={}, object=nil)
        @klass = klass
        @type = type
        @options = options
        @object = object; @procs_run = 0
      end

      # # # # # # # # # # # # # # # # # # # # # # # # # #
      begin # Chainable methods that all return the association object. Use these to form your associations.
      # If the association has already been tied to an object, a modified duplicate will be returned instead.

      # Sets association attributes that are based on the primary object. These are used both for finding
      # associated objects and for creating a new association.
      def primary(options={})
        @primary_options = primary_options(false).merge(options)
        @procs_run = 0
        self
      end

      # Sets association attributes that are based on the foreign object. These are used both for finding
      # associated objects and for creating a new association.
      def foreign(options={})
        @foreign_options = foreign_options(false).merge(options)
        @procs_run = 0
        self
      end

      # Sets finder_options that are based on the foreign object. These are used only for finding associated objects.
      def scope(options={})
        @foreign_scope = foreign_scope(false).merge(options)
        @procs_run = 0
        self
      end

      # Add a proc to be run before using the association on an object. The proc is called with two arguments:
      # the first argument is this association, the second argument is the object the association is being called on.
      def dynamic(&block)
        dynamic_procs << block
        @procs_run = 0
        self
      end

      # Sets the association to 'act as' a different name. For association macros such as has_one and has_many, it will
      # affect the name of the foreign_key. If there is no mirrored association specified, this name is also used as
      # the mirrored association name.
      def as(association_name)
        @act_as = association_name
        @procs_run = 0
        self
      end

      # Sets the association to mirror another named association in the associated class.
      def mirrors(association_name)
        @mirrored_association_name = association_name
        @procs_run = 0
        self
      end
      end
      # # # # # # # # # # # # # # # # # # # # # # # # # #

      # # # # # # # # # # # # # # # # # # # # # # # # # #
      # Accessor Methods

      def inspect # :nodoc:
        run_dynamic_procs
        super
      end

      def primary_options(run_dynamic=true)
        @primary_options ||= {}
        run_dynamic_procs if run_dynamic
        @primary_options
      end
      def foreign_options(run_dynamic=true)
        @foreign_options ||= {}
        run_dynamic_procs if run_dynamic
        @foreign_options
      end
      def foreign_scope(run_dynamic=true)
        @foreign_scope ||= {}
        run_dynamic_procs if run_dynamic
        @foreign_scope
      end

      # Returns the class associated, if it is found.
      def associated_klass
        @associated_klass ||= Object.module_eval("::#{Inflector.camelize(@options[:class_name].to_s)}", __FILE__, __LINE__)
      end

      # This is a very key method that creates an association set based on an object and the association.
      # If you call it with an instance, it will dup the association for the set; If this association is
      # already applied to an object, it creates an association set.
      def set(instance=nil)
        if instance
          apply_to(instance).set
        elsif @object
          @type == :many ? Set.new(@object, self) : Instance.new(@object, self)
        else
          raise ArgumentError, "must include instance"
        end
      end

      def mirrored_association_name
        @mirrored_association_name || @act_as
      end

      def mirrored_association
        return nil unless @mirrored_association_name || @act_as
        @mirrored_association || begin
          @procs_run = 0 # Just another place to reset this -- a dynamic proc could rely on a mirrored_association, after all...
          @mirrored_association = associated_klass.associations[@mirrored_association_name || @act_as]
        end
      end

      def act_as
        @act_as || @mirrored_association_name
      end

      def primary?
        !primary_options.empty?
      end
      def foreign?
        !foreign_options.empty?
      end

      # The current finder_options used for finding associated objects. It simply combines primary, foreign, and scope.
      # This is public only for debugging purposes.
      def finder_options(run_dynamic=true)
        primary_options(run_dynamic).merge(foreign_options(run_dynamic)).merge(foreign_scope(run_dynamic)).inject({}) do |h,(k,v)|
          h[k] = (@object && v.is_a?(Symbol) && @object.respond_to?(v)) ? @object.send(v) : v
          h
        end
      end
      # # # # # # # # # # # # # # # # # # # # # # # # # #

      # Ties the association definition with a primary object.
      # This will allow for any options based on the object itself to be determined before running the query for associated objects.
      def apply_to(object)
        applied = dup
        applied.instance_variable_set(:@object, object)
        applied.instance_variable_set(:@procs_run, 0)
        applied
      end

      # This is a powerful method that merges two associations into one new association.
      def merge(other)
        raise ArgumentError, "must be an association definition object" unless other.is_a?(SimpleMapper::Associations::Association)
        # self.class.new(@klass, :many)
        other
      end

      private
        def run_dynamic_procs
          !@object || @procs_run == dynamic_procs.length || begin
            pre_find = finder_options(false)
            dynamic_procs.each {|p| p.call(self,@object)}
            post_find = finder_options(false)
            @procs_run = dynamic_procs.length if !post_find.empty? && pre_find == post_find
          end
        end
        def dynamic_procs
          @dynamic_procs = (@dynamic_procs || []).reject {|p| !p.is_a?(Proc)}
        end

      public
      class Instance
        attr_accessor :association
        
        def initialize(instance, association)
          @instance = instance
          @association = association
          @items = nil
          @loaded = false
        end

        def method_missing(method, *args)
          (item || items).send(method, *args)
        end

        def dirty?
          @items && @items.any? { |item| item.dirty? }
        end

        def associate!(object)
          associate(object)
          object.save
        end
        def associate(object,associate_other=true)
          # puts "Associating #{@instance.inspect} << #{object.inspect} (#{@association.primary? ? 'Primary' : ''} / #{@association.foreign? ? 'Foreign' : ''})\n#{@association.inspect}"
          # 1) Set the @association.primary attributes to @instance
          if @association.primary?
            # puts "Primary options: #{@association.primary_options.inspect}"
            @association.primary_options.each do |atr,k|
              # puts "\tSetting instance##{k} = #{object.respond_to?(atr) ? object.send(atr) : atr}"
              @instance.send("#{k}=", object.send(atr)) if @instance.respond_to?("#{k}=") && object.respond_to?(atr)
            end
          end
          # 2) Set the @association.foreign attributes to object
          if @association.foreign?
            # puts "Foreign options: #{@association.foreign_options.inspect}"
            @association.foreign_options.each do |k,atr|
              # puts "\tSetting object##{k} = #{@instance.respond_to?(atr) ? @instance.send(atr) : atr}"
              object.send("#{k}=", @instance.respond_to?(atr) ? @instance.send(atr) : atr) if object.respond_to?("#{k}=")
            end
          end
          # 3) If there is a @association.mirrored_association, call object.association_set(@association.mirrored_association_name).associate(@instance,false) on it.
          if associate_other && @association.mirrored_association
            object.association_set(@association.mirrored_association_name).associate(@instance,false)
          end
          (@items ||= []) << object
        end
# REWRITE
        # def disassociate(item=nil)
        #   dis_items = item || items
        #   (dis_items.is_a?(Array) ? dis_items : [dis_items]).each do |item|
        #     item.instance_variable_set("@#{@association.foreign_key}", nil) unless item.new_record? || @association.foreign_key == :none
        #     @items = @items - [item]
        #   end
        #   item || items
        # end
        def build(options)
          associate(@association.associated_klass.new)
        end
        def create(options)
          object = @association.associated_klass.new
          associate(object)
          object.save
        end
        def reload!
          @items = nil
          @loaded = false
          true
        end

        def respond_to?(symbol)
          (item || items).respond_to?(symbol) || super
        end

        def items
          # This will look more like it was made for set
          @items || begin
            @items = @association.associated_klass.all(@association.finder_options)
            @loaded = true
          end
          @items
        end
        def item
          items.length == 1 ? items[0] : nil
        end

        def inspect
          (item || items).inspect
        end
      end

      class Set < Instance
        include Enumerable

        def each
          items.each { |item| yield item }
        end

        def <<(object)
          (@items ||= []) << associate(object)
        end
      end
    end
  end
end
