require 'sinatra'

module Sinatra
  module MinimalAuthentication
    def init_auth(realm, &check)
      @realm, @check = realm, check
    end

    def unauthorized!
      response.headers['WWW-Authenticate'] = 'Basic realm="%s"' % @realm
      throw :halt, [ 401, 'Authorization Required' ]
    end

    def bad_request!
      throw :halt, [ 400, 'Bad Request' ]
    end

    def user
      request.env['REMOTE_USER']
    end

    def authorized?
      user
    end

    def authorize!
      return if authorized?
      auth = Rack::Auth::Basic::Request.new(request.env)
      unauthorized! unless auth.provided?
      bad_request! unless auth.basic?
      unauthorized! unless @check.call(*auth.credentials)
      request.env['REMOTE_USER'] = auth.username
    end
  end
end
