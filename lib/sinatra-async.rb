require 'sinatra'
require 'eventmachine'

module Sinatra
  module AsyncRequests
    def self.included(other)
      other.extend(self)
    end

    %w(before after).each do |method|
      define_method(method) do |path=nil, opts={}, &bk|
        super(path, opts, &bk)
        if path
          new_path = prefix_path('/async', path)
          super(new_path, opts, &bk)
        end
      end
    end

    %w(get post head options put).each do |method|
      define_method(method) do |path, opts={}, &bk|
        super(path, opts, &bk)
        new_path = prefix_path('/async', path)
        super(new_path, opts) do |*args|
          EM.defer { self.instance_exec(*args, &bk) }
          nil
        end
      end
    end

   private

    def prefix_path(prefix, path)
      if path.is_a? Regexp
        stripped = path.source.gsub(/^\^/, '')
        %r{^#{Regexp.escape(prefix)}#{stripped}}
      else
        prefix + path
      end
    end
  end
end
