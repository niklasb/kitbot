require 'syncutils'

module IrcBot::Commands
  def say(msg, target)
    raise ArgumentError, 'No target given' if !target
    synchronize do
      throttle
      cmd_privmsg target, msg
      @send_times << Time.now
    end
  end

  def join(channel)
    synchronize do
      wait_for_line(/^:#{@nick}(!\S+)\s+JOIN\s+:?#{channel}/i) do
        cmd_join channel
      end
    end
  end

  def quit(msg='Bye')
    synchronize do
      wait_for_line(/^:#{@nick}(!\S+)\s+QUIT(\s+.*)?/i) do
        cmd_quit msg
      end
    end
    @conn.close
  end

  def get_users(channel)
    assert_connected
    synchronize do
      users = []
      SyncUtils.await do |ev|
        h = push_handler(/^:\S+ (315|352) (.*)/) { |status, args|
          if status == '315'
            h.remove
            ev.signal
          else
            users << args.split[5]
          end
        }
        cmd_who channel
      end
      users
    end
  end

  def get_topic(channel)
    status, topic = wait_for_line(/^:\S+ (4\d\d|332|331) \S+ \S+ :?(.*)/) {
      cmd_topic channel
    }

    case status
    when '332' then topic
    when '331' then ''
    else nil
    end
  end

  def method_missing(m, *args)
    if m =~ /^cmd_([a-z]+)$/
      return send_line(quote_cmd([$1.upcase, *args]))
    end
    raise NoMethodError, 'No such method: %s' % m
  end

 protected

  def quote_cmd(args)
    last_arg = args.pop
    if args.any? { |a| a =~ /\s:/ }
      raise ArgumentError, 'Only the last argument can contain whitespace'
    end
    last_arg = ':' + last_arg if last_arg =~ /\s|:/
    [*args, last_arg].join(' ')
  end
end
