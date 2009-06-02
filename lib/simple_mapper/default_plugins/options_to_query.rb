require 'cgi'
# This simply defines some extensions to various objects to enable smartly converting values to a
# standard query string understandable by Rails and Merb.
# First the structural base:
class Object
  def to_param #:nodoc:
    to_s
  end
  def to_query(key) #:nodoc:
    "#{CGI.escape(key.to_s)}=#{CGI.escape(to_param || "")}"
  end
end
class Array
  def to_query(key) #:nodoc:
    collect { |value| value.to_query("#{key}[]") } * '&'
  end
end
class Hash
  def to_query(namespace=nil)
    collect do |key, value|
      value.to_query(namespace ? "#{namespace}[#{key}]" : key)
    end * '&'
  end
end

# And then some specifics:
require 'time'
class Time
  def to_param
    xmlschema
  end
end
