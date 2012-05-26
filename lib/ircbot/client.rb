module IrcBot
  class IrcError < Exception; end

  module BasicClient
   protected

    def init_client(nick)
      @nick = nick

      push_handler(/^PING :(.+)$/) { |ping| cmd_pong ping }
      push_handler /^(?::\S+\s+)?(4\d\d)\s+(.*)/ do |errno, err|
        raise IrcError, 'IRC error %s: %s' % [errno, err]
      end
    end

    def identify
      synchronize do
        wait_for_line(/^(?::\S+\s+)?376\s+/) do
          cmd_user [@nick, '0', '*', @nick]
          cmd_nick @nick
        end
      end
    end
  end
end
