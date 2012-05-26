require 'socket'
require 'test/unit/assertions'
require 'monitor'

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

    def start(server, port=6667)
      @conn = TCPSocket.open(server, port)
      Thread.new { main_loop }
      identify
    end

  protected

    def main_loop
      loop { handle_line(get_line) }
    end

    def synchronize(&block)
      (@mutex ||= Monitor.new).synchronize(&block)
    end

    def assert_connected
      assert @conn, 'Not connected'
    end
  end
end
