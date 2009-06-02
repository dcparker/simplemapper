require 'simple_mapper/support/bliss_serializer'
require 'rubygems'
gem 'formattedstring'
require 'formatted_string'

module SimpleMapper
  module XmlFormat
    def self.included(base)
      base.extend ClassMethods
    end

    def self.mime_type_headers
      {'Accept' => 'application/xml', 'Content-type' => 'application/xml'}
    end

    def to_xml
      xml = Serialize.object_to_xml(self, :key_name => 'self').to_s
      # puts "POST XML: #{xml}"
      xml
    end

    module ClassMethods
      # This assumes a standard xml format:
      #   <person attribute="">
      #     <another_att>value</another_att>
      #   </person>
      # And for a collection of objects:
      #   <people>
      #     <person attribute="">
      #       <another_att>value 1</another_att>
      #     </person>
      #     <person attribute="">
      #       <another_att>value 2</another_att>
      #     </person>
      #   </people>
      def from_xml(xml)
        doc = Serialize.hash_from_xml(xml)
        # doc could include a single 'model' element, or a 'models' wrapper around several.
        puts "Top-level XML key(s): #{doc.keys.inspect}" if @debug
        if doc.is_a?(Hash)
          # By specification the doc should have only ONE top-level element (key)
          key = doc.keys.first
          if doc[key] && doc[key].keys.uniq == [key.singularize] && doc[key][key.singularize].is_a?(Array)
            puts "Several objects returned under key '#{key}'/'#{key.singularize}':" if @debug
            doc[key][key.singularize].collect do |e|
              puts "Obj: #{e.inspect}" if @debug
              Object.module_eval("::#{key.singularize.camelize}", __FILE__, __LINE__).load(e)
            end
          elsif doc[key] # top-level must be single object
            Object.module_eval("::#{key.singularize.camelize}", __FILE__, __LINE__).load(doc[key])
          else
            nil
          end
        else # doc isn't a hash, probably nil
          doc
        end
      end
    end
  end
end
