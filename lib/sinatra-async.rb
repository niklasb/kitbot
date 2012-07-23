require 'sinatra'
require 'eventmachine'

module Sinatra
  module AsyncRequests
    def self.included(other)
      other.extend(self)
    end

    %w(get post head options put).each do |method|
      define_method(method) do |path, opts={}, &bk|
        super(path, opts, &bk)
        super('/async' + path, opts) do
          EM.defer(&bk)
          nil
        end
      end
    end
  end
end
