require 'ruby2ruby'

class Object
  # Calls the block in the context of self, and returns self.
  def extended(*args, &block)
    self.send(:eval, block.to_ruby).call(*args)
    self
  end
end

class Proc
  # Changes the context of a proc so that 'self' is the klass_or_obj passed.
  def in_context(klass_or_obj)
    klass_or_obj.send(:eval, self.to_ruby)
  end
end

class Hash
  def stringify_keys(specials={})
    self.dup.stringify_keys!(specials)
  end
  def stringify_keys!(specials={})
    self.each_key do |k|
      self[specials.has_key?(k) ? specials[k] : k.to_s] = self.delete(k)
    end
    self
  end

  # Symbolize keys
  def symbolize_keys!
    self.each_key do |k|
      self[k.to_sym] = self.delete(k)
    end
    self
  end
  def symbolize_keys
    {}.merge(self).symbolize_keys!
  end

  def except(*keys)
    reject {|k,v| keys.flatten.include?(k) }
  end

  def crawl(&block)
    raise ArgumentError, "no block given" unless block_given?
    self.each do |k,v|
      case block.arity
      when 1
        yield(v)
      when 2
        yield(k,v)
      when 3
        yield(self,k,v)
        v = self[k]
      end
      if v.is_a?(Array)
        v.crawl(&block)
      elsif v.is_a?(Hash)
        v.crawl(&block)
      end
    end
  end
end

class Array
  def except(element)
    reject {|e| e == element}
  end

  def crawl(&block)
    raise ArgumentError, "no block given" unless block_given?
    self.each do |v|
      k = self
      v = case block.arity
      when 1
        yield(v)
      when 2
        yield(k,v)
      when 3
        yield(self,k,v)
      end
      if v.is_a?(Array)
        v.crawl(&block)
      elsif v.is_a?(Hash)
        v.crawl(&block)
      end
    end
  end
end

module Enumerable
  def group_by
    inject({}) do |groups, element|
      (groups[yield(element)] ||= []) << element
      groups
    end
  end if RUBY_VERSION < '1.9'  
end
