require 'net/http'
require 'uri'
require 'simple_mapper/default_plugins/callbacks'
require 'simple_mapper/default_plugins/options_to_query'

# SimpleMapper::HttpAdapter.
# Input:
#   get is called with finder options
#   put and post are called with data
#   delete is called with an identifier
# Simply perform the requests, with callbacks, to the appropriate http host.
module SimpleMapper
  class HttpAdapter
    attr_accessor :base_url
    attr_accessor :raise_http_errors

    alias :set_base_url :base_url=
    def base_uri
      URI.parse(base_url)
    end

    def headers
      @headers ||= {}
    end
    def headers=(v)
      raise TypeError, "headers set must be a hash" unless v.is_a?(Hash)
      headers.merge!(v)
    end
    alias :set_headers :headers=

    def finder_options
      @finder_options ||= {}
    end
    def finder_options=(options)
      raise TypeError, "options must be a hash!" unless options.is_a?(Hash)
      @finder_options = options
    end
    alias :set_finder_options :finder_options=
    def display_options
      @display_options ||= {}
    end
    def display_options=(options)
      raise TypeError, "options must be a hash!" unless options.is_a?(Hash)
      @display_options = options
    end
    alias :set_display_options :display_options=

    def get(options={})
      raw_get(base_uri.path + query_string_from_options(finder_options.merge(display_options.merge(options))))
    end

    def raw_get(url)
      begin
        http.request(request('get', url)).body
      rescue => e
        raise e if !!raise_http_errors
        nil
      end
    end

    def put(identifier,data,options={})
      begin
        http.request(request('put', URI.parse(identifier).path + query_string_from_options(display_options.merge(options)), data)).body
      rescue => e
        raise e if !!raise_http_errors
        nil
      end
    end

    def post(data,options={})
      begin
        http.request(request('post', base_uri.path + query_string_from_options(display_options.merge(options)), data)).body
      rescue => e
        raise e if !!raise_http_errors
        nil
      end
    end

    # In the http adapter, the identifier is a url.
    def delete(identifier,options={})
      begin
        http.request(request('delete', URI.parse(identifier).path + query_string_from_options(options))).body
      rescue => e
        raise e if !!raise_http_errors
        nil
      end
    end

    private
      def query_string_from_options(options={})
        options.empty? ? '' : ('?' + options.to_query)
      end

      def http(refresh=false)
        @http = Net::HTTP.new(base_uri.host, base_uri.port) if @http.nil? || refresh
        @http
      end

      def request(verb,path,body=nil,options={})
        request_class = Net::HTTP.const_get verb.to_s.capitalize
        request = request_class.new path
        request.body = body
        request.initialize_http_header headers.merge(options[:headers] || {})
        # - - - after_request_instantiate callback
        res = run_callback('initialize_request', request)
        request = res if res.is_a?(request.class)
        # - - -
        request
      end
  end
end
