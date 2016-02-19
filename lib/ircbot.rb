require 'monitor'
require 'openssl'
require 'socket'
require 'test/unit/assertions'

module IrcBot; end
require 'ircbot/line_based'
require 'ircbot/client'
require 'ircbot/commands'
require 'ircbot/hooks'
require 'ircbot/throttle'

module IrcBot
  class Bot
    include Test::Unit::Assertions

    include BasicClient
    include Throttling
    include Commands
    include Hooks
    include LineBasedProtocol

    def initialize(nick, config = {})
      init_client(nick)
      init_throttling(config)
      init_hooks
    end

    def start(server, port=6667, ssl=false)
      @conn = TCPSocket.open(server, port)
      @ssl = ssl
      if ssl
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
        @conn = OpenSSL::SSL::SSLSocket.new(@conn, ctx)
        @conn.sync_close = true
        @conn.connect
      end
      Thread.new { main_loop }
      identify
    end

  protected

    def main_loop
      loop { handle_line(get_line) }
    end

    def readline
      @conn.readline
    end

    def write(data)
      if @conn.is_a?(OpenSSL::SSL::SSLSocket)
        @conn.write(data)
      else
        @conn.send(data, 0)
      end
    end

    def synchronize(&block)
      (@mutex ||= Monitor.new).synchronize(&block)
    end

    def assert_connected
      assert @conn, 'Not connected'
    end
  end
end
