require 'rubygems'
require 'oauth'
require 'oauth/consumer'
require 'oauth/client/net_http'

# First some fixes...
module OAuth
  module Signature
    class Base
      def initialize(request, options = {}, &block)
        raise TypeError unless request.kind_of?(OAuth::RequestProxy::Base)
        @request = request
        if block_given?
          @token_secret, @consumer_secret = yield block.arity == 1 ? token : [token, consumer_key,nonce,request.timestamp]
        else
          @consumer_secret = options[:consumer].respond_to?(:secret) ? options[:consumer].secret : options[:consumer]
          @token_secret = options[:token].respond_to?(:secret) ? options[:token].secret : (options[:token] || '')
        end
      end
    end
  end

  module RequestProxy
    class Base
      def inspect
        "#<OAuth::RequestProxy::MerbRequest:#{object_id}\n\tconsumer_key: #{consumer_key}\n\ttoken: #{token}\n\tparameters: #{parameters.inspect}\n>"
      end
    end
  end
end

module SimpleMapper
  module Oauth
    def requires_oauth(consumer_key, consumer_secret, options={})
      @consumer_key = consumer_key
      @consumer_secret = consumer_secret
      @oauth_options = options || {}

      # Ingeniousity here... ;)
      # Duplicates the class to give it a temporary session-attached oauth scope, sets oauth to the Model-Controller-OAuth class,
      # then makes the class use the original class for all of its instantiation.
      # NOTE: This only really makes the class methods use OAuth. Object methods, like associations, won't play the trick as well.
      def self.with_oauth(controller)
        duped = self.dup
        duped.set_oauth(controller)
        yield if block_given?
        duped
      end

      def oauth
        @oauth
      end

      def set_oauth(controller)
        @oauth = OAuthController.new(controller, self, @consumer_key, @consumer_secret, @oauth_options)
        add_callback('initialize_request') do |request|
          @oauth.authenticate! if !@oauth.authorized? && @oauth.scriptable?
          raise RuntimeError, "Must authorize OAuth before attempting to get data from the provider." unless @oauth.authorized?
          @oauth.request_signed!(request)
        end
        @oauth
      end

      true
    end
  end

  class HttpAdapter
    include Oauth
  end
end

# We'll have an instance of these for each controller-model pair.
class OAuthController
  DEFAULT_OPTIONS = {
    # Signature method used by server. Defaults to HMAC-SHA1
    :signature_method=>'HMAC-SHA1',

    # default paths on site. These are the same as the defaults set up by the generators
    :request_token_path=>'/oauth/request_token',
    :authorize_path=>'/oauth/authorize',
    :access_token_path=>'/oauth/access_token',

    # How do we send the oauth values to the server see 
    # http://oauth.googlecode.com/svn/spec/branches/1.0/drafts/6/spec.html#consumer_req_param for more info
    #
    # Possible values:
    #
    #   :authorize - via the Authorize header (Default) ( option 1. in spec)
    #   :post - url form encoded in body of POST request ( option 2. in spec)
    #   :query - via the query part of the url ( option 3. in spec)
    :auth_method=>:authorize, 

    # Default http method used for OAuth Token Requests (defaults to :post)
    :http_method=>:post, 

    :version=>"1.0",

    # Default authorization method: have the controller redirect to the authorize_url.
    :authorization_method => lambda {|model| redirect(model.oauth.consumer.authorize_url)},

    # Default session: grab session from the controller's session method -- session['Person_oauth'] for the Person ActiveResource model.
    :session => lambda {|model| session[model.name.to_s + '_oauth'] ||= {} }
  }
  attr_accessor :options, :consumer

  def initialize(controller, model, consumer_key, consumer_secret, options={})
    @controller = controller
    @options = DEFAULT_OPTIONS.merge(options)
    @model = @options.delete(:model) || model
    @consumer = OAuth::Consumer.new(consumer_key, consumer_secret, options)
  end

  def authorized?
    !!session[:access_token]
  end

  def scriptable?
    @options[:authorization_method] == :scriptable
  end

  # The session is what holds which models are authenticated with what tokens.
  # We just need the controller to retreive the session and to send back redirects when necessary.
  def authenticate!
    # 1) If we have no tokens, get a request_token and run the authorization method.
    # 2) If we have a request_token, assume the user has already answered the question, go ahead and try to get an access_token.
    if access_token
      return true
    elsif request_token
      return @controller.begin_pathway(@options[:authorization_method].in_context(controller).call(@model)) if @options[:authorization_method].is_a?(Proc)
      return true if access_token # For scriptables
    else
      raise RuntimeError, "It seems there is a problem between your OAuth client and the OAuth provider you are contacting. Inspect the naming of the token and token secret parameters being sent by the website."
    end
  end

  def request_signed!(request)
    @consumer.sign!(request, current_token)
    request
  end

  private
    # If none exist, go ahead and get one.
    def request_token
      session[:request_token] || begin
        token = @consumer.get_request_token
        session[:request_token] = token if token.token && token.secret
        session[:request_token]
      end
    end

    # If none exist but request_token exists, go ahead and request one.
    def access_token
      return nil if session[:request_token].nil?
      session[:access_token] || begin
        token = session[:request_token].get_access_token
        session[:access_token] = token if token.token && token.secret
        session[:access_token]
      end
    end

    def current_token
      access_token || request_token
    end

    def session
      @session || begin
        @session = @options[:session].in_context(@controller).call
      end
    end
end
