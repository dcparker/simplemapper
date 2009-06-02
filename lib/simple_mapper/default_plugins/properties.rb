module SimpleMapper
  # Properties sets up a structure of properties such that:
  # 1. You name an identifier and several properties that will be used in your model, and
  # 2. properties do not include the identifier
  # Properties are accessed and set through method_missing, simply using instance variables to
  # store each property value. If you wish, you can define your own accessor method for any
  # property and it will be used instead.
  # 
  # The methods data and data= are provided and perform the usual logical behavior for a model that
  # has properties == it receives a hash and calls the appropriate methods on the object according
  # to the keys in that hash, when they match up with a defined property. data simply calls to_hash,
  # which performs the opposite, simply collecting the properties into a hash by calling the appropriate
  # accessor methods.
  module Properties
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def properties(*property_names)
        if property_names.length > 0
          property_names.each {|e| property e.to_s}
        else
          @properties ||= []
        end
      end

      def property(property_name)
        properties << property_name.to_sym
      end

      def identifier(id=nil)
        @identifier = id.to_s unless id.nil?
        @identifier
      end
    end

    def data(options={})
      to_hash(options)
    end

    # Sets the data into the object. This is provided as a default method, but your model can overwrite it any
    # way you want. For example, you could set the data to some other object type, or to a Marshalled storage.
    # The type of data you receive will depend on the format and parser you use. Of course you could make up
    # your own spin-off of one of those, too.
    def data=(data)
      raise TypeError, "data must be a hash" unless data.is_a?(Hash)
      data.each {|k,v| instance_variable_set("@#{k}", v)}
    end
    alias :update_data :data=

    def to_hash(options={})
      self.class.properties.inject({}) {|h,k| h[k] = instance_variable_get("@#{k}"); h}
    end

    def identifier
      instance_variable_get("@#{self.class.identifier}")
    end

    def method_missing(method, *args)
      if self.class.properties.include?(method)
        instance_variable_get("@#{method}")
      elsif method.to_s =~ /=$/ && self.class.properties.include?(method.to_s.gsub(/=/, '').to_sym)
        instance_variable_set("@#{method.to_s.gsub(/=/, '')}", *args)
      else
        super
      end
    end
  end
end