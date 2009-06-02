require File.expand_path(File.dirname(__FILE__) + '/persistence')
module SimpleMapper
  class Base
    def self.inherited(klass)
      SimpleMapper::Persistence::prepare_for_inheritance(klass)
      klass.send(:include, SimpleMapper::Persistence)
    end
  end
end
