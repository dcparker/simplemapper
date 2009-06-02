require 'simple_mapper/support/bliss_serializer'
require 'rubygems'
gem 'formattedstring'
require 'formatted_string'

module SimpleMapper
  module JsonFormat
    def self.included(base)
      base.extend ClassMethods
    end

    def self.mime_type_headers
      {'Accept' => 'application/json', 'Content-type' => 'application/json'}
    end

    def to_json
      json = Serialize.object_to_json(self, :key_name => 'self').to_s
      # puts "POST JSON: #{json}"
      json
    end

    def meta
      @meta
    end

    module ClassMethods
      # This assumes a standard json format:
      #   {'person':{'attribute':'','another_att':'value'}}
      # And for a collection of objects:
      #   {'people':[{'person':{'attribute':'','another_att':'value 1'}},{'person':{'attribute':'','another_att':'value'}}]}
      def from_json(json)
        doc = Serialize.hash_from_json(json)
        # doc could include a single 'model' element, or a 'models' wrapper around several.
        if doc.is_a?(Hash)
          # In contrast to XML, JSON is not restricted to one top-level key. We will assume the objects are in a hash/array
          # referenced by either singular or plural of the klass.
# puts "Received #{doc.length} bytes of json. Top keys: #{doc.keys.join(', ')}. Looking for '#{self.entity_name.underscore}' or '#{self.entity_name.pluralize.underscore}'"
          meta = doc.dup
          key = if doc[self.entity_name.underscore]
            self.entity_name.underscore
          elsif doc[self.entity_name.pluralize.underscore]
            self.entity_name.pluralize.underscore
          end
          return nil if key.nil?
# puts "JSON has #{key}"
          meta.delete(key) # removing the data leaves us only the meta information
          meta.freeze
          ret = if doc[key].is_a?(Array)
            doc[key].collect do |e|
              obj = self.load(e)
              obj.instance_variable_set(:@meta, meta)
              obj
            end
          else
            obj = self.load(doc[key])
            obj.instance_variable_set(:@meta, meta)
            obj
          end
# puts "Collected: #{(ret.is_a?(Array) ? ret : [ret]).length} objects"; ret
        else # doc isn't a hash, probably nil
          doc
        end
      end
    end
  end
end
