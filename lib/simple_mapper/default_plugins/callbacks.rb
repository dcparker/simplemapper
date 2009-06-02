module SimpleMapper
  module CallbacksExtension
    def callbacks
      @callbacks ||= Hash.new {|h,k| h[k] = []}
    end
    def add_callback(name,&block)
      callbacks[name] << block
    end
    def run_callback(name, *args)
      args = args.first if args.length == 1
      callbacks[name].inject(args) {|args,cb| cb.call(*args) || args}
    end
  end
  class HttpAdapter
    include CallbacksExtension
  end
end
