module SimpleMapper
  module PluginSupport
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      # Requires the plugin mentioned, then includes it in the calling class or module.
      # The require step is rescued, so if you have your own plugin you can still use this to include your plugin after you've required it.
      def include_plugin(plugin_name)
        require "simple_mapper/default_plugins/#{plugin_name.to_s}" rescue nil
        include Object.module_eval("::SimpleMapper::#{plugin_name.to_s.camelize}", __FILE__, __LINE__)
      end
      alias :has :include_plugin
      alias :uses :include_plugin
      alias :acts_as :include_plugin
    end
  end
end
