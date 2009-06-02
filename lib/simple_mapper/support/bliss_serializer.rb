require 'rexml/light/node'
require 'rexml/document'
gem 'formattedstring'
require 'formatted_string'
gem 'hash_magic'
require 'hash_magic'

module Serialize
  XML_OPTIONS = {
    :include_key => false, # Can be false, :element, or :attribute
    :report_nil => true, # Sets an attribute nil="true" on elements that are nil, so that the reader doesn't read as an empty string
    :key_name => :id, # Default key name
    :instance_columns => :visible_properties,
    :class_columns => :visible_properties,
    :default_root => 'xml',
  }
  def self.object_to_xml(obj, options={})
    options = options.reverse_merge!(obj.class.xml_options) if obj.class.respond_to?(:xml_options)
    options = options.reverse_merge!(obj.xml_options) if obj.respond_to?(:xml_options)
    to_xml(obj.to_hash(options), {:root => Inflector.underscore(obj.class.name)}.merge(options))
  end
  def self.to_xml(attributes={}, options={})
    options = XML_OPTIONS.merge(options)
    root = options[:root]
    attributes.reject! {|k,v| options[:exclude].include?(k)}

    doc = REXML::Document.new
    root_element = doc.add_element(root || 'xml')

    case options[:include_key]
    when :attribute
      root_element.add_attribute(options[:key_name].to_s, attributes.delete(options[:key_name].to_s).to_s).extended do
        def self.to_string; %Q[#@expanded_name="#{to_s().gsub(/"/, '&quot;')}"] end
      end
    when :element
      root_element.add_element(options[:key_name].to_s) << REXML::Text.new(attributes.delete(options[:key_name].to_s).to_s)
    end

    attributes.each do |key,value|
      if value.nil?
        node = root_element.add_element(key.to_s)
        node.add_attribute('nil', 'true') if options[:report_nil]
      else
        if value.respond_to?(:to_xml)
          assoc_options = {}
          assoc_options = {:exclude => value.association.foreign_key_column.name} if value.respond_to?(:association)
          root_element.add_element(REXML::Document.new(value.to_xml(assoc_options.merge(:root => key.to_s)).to_s))
        else
          root_element.add_element(key.to_s) << REXML::Text.new(value.to_s.dup)
        end
      end
    end

    root ? doc.to_s : doc.children[0].children.to_s
  end
  def self.hash_from_xml(xml,options={})
    xml.to_s.formatted(:xml).to_hash
  end

  JSON_OPTIONS = {
    :include_key => false, # Can be true or false
    :key_name => :id, # Default key name
    :instance_columns => :visible_properties,
    :class_columns => :visible_properties,
  }
  def self.object_to_json(obj, options={})
    options = options.reverse_merge!(obj.class.json_options) if obj.class.respond_to?(:json_options)
    options = options.reverse_merge!(obj.json_options) if obj.respond_to?(:json_options)
    to_json(obj.to_hash(options), options)
  end
  def self.to_json(attributes={}, options={})
    attributes = attributes.to_hash if attributes.respond_to?(:to_hash)
    options = JSON_OPTIONS.merge(options)
    options[:exclude] = [options[:exclude]].flatten.compact.collect {|e| e.to_s}
    attributes.reject! {|k,v| options[:exclude].include?(k)}
    options[:root] ? JSON.unparse({options[:root] => attributes}) : JSON.unparse(attributes)
  end
  def self.hash_from_json(json,options={})
    json.to_s.formatted(:json).to_hash
  end
end

class Hash
  def to_xml(options={})
    options[:root] = keys.length == 1 ? keys[0] : nil if !options.has_key?(:root)
    Serialize.to_xml(self.slashed, options.merge(:root => (options.has_key?(:root) ? options[:root] : 'xml')))
  end
end

class Array
  def to_xml(options={})
    collect {|e| e.to_xml(options)}.join('')
  end
end

class Time
  def to_xml
    xmlschema
  end
end

module Merb
  class Request
    def xml_params
      @xml_params ||= begin
        if Merb::Const::XML_MIME_TYPE_REGEXP.match(content_type)
          Serialize.hash_from_xml(raw_post) rescue Mash.new
        end
      end
    end
  end
end
