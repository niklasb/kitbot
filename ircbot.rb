require 'socket'
require 'test/unit/assertions'
require 'set'
require 'dynamic_binding'

class IrcError < Exception ; end

class IrcBot
  include Test::Unit::Assertions

  @cmds = %w{ join kick mode nick notice ping pong privmsg quit user }

  def initialize(nick, config = {})
    @config = {
      delay: 0.1,
      throttle_threshold_time: 2,
      throttle_threshold_messages: 5,
      throttle_factor: 10,
      throttle_time: 10,
    }.merge(config)

    @nick = nick
    @conn = nil
    @send_times = []
    @throttle_end = Time.now

    @join_hooks = []
    @leave_hooks = []
    msg_hooks = @msg_hooks = []

    add_msg_hook /^\.help$/, ".help" do
      say_chan "I understand: %s" % msg_hooks.map { |_,h,_| h }
                                             .reject(&:nil?).join(', ')
    end
  end

  def assert_connected
    assert @conn, "Not connected!"
  end

  def send(msg)
    assert_connected
    puts "> %s" % msg
    @conn.send msg + "\n", 0
  end

  def decode(str)
    str = str.dup
    ['utf-8', 'iso-8859-1'].each do |enc|
      str.force_encoding enc
      return str if str.valid_encoding?
    end
    return str.encode('ascii', :invalid => :replace, :undef => :replace, :replace => '')
  end

  def get_line
    assert_connected

    loop do
      line = decode(@conn.readline).strip
      puts "< " + line
      # handle PING transparently
      return line unless handle_line(line)
    end
  end

  def handle_line(line)
    case line
    when /^PING :(.+)$/i
      puts "[ Server ping ]"
      cmd_pong $1
    when /^(:\S+\s+)?4\d\d\s+/
      $stderr.puts "[!!] IRC error: %s" % line
    else
      return nil
    end
    return true
  end

  def wait_for_line(pattern)
    loop do
      line = get_line
      return line, *$~.captures if line =~ pattern
    end
  end

  def quote_cmd(args)
    last_arg = args.pop
    if args.any? { |a| a =~ /\s:/ }
      raise ArgumentError, "Only the last argument can contain whitespace"
    end
    last_arg = ":%s" % last_arg if last_arg =~ /\s|:/
    [*args, last_arg].join(" ")
  end

  @cmds.each do |cmd|
    define_method "cmd_%s" % cmd do |*args|
      send(quote_cmd([cmd.upcase, *args]))
    end
  end

  def delay
    now = Time.now
    @send_times = @send_times.drop_while { |t|
      now - t > @config[:throttle_threshold_time]
    }
    if @send_times.size > @config[:throttle_threshold_messages]
      @throttle_end = now + @config[:throttle_time]
    end

    @config[:delay] * (now < @throttle_end ? @config[:throttle_factor] : 1)
  end

  def say(msg, target)
    raise ArgumentError, "No target given" if !target
    sleep delay
    cmd_privmsg target, msg
    @send_times << Time.now
  end

  def connect(server, port=6667)
    @conn = TCPSocket.open(server, port)
    cmd_user [@nick, "0", "*", @nick]
    cmd_nick @nick
    wait_for_line(/^(:\S+\s+)?376\s+/)
  end

  def join(channel)
    channel = '#' + channel unless channel[0,1] == '#'
    cmd_join channel
    wait_for_line(/^:#{@nick}(!\S+)\s+JOIN\s+:?#{channel}/i)
  end

  def quit(msg="Bye")
    cmd_quit msg
    wait_for_line(/^:#{@nick}(!\S+)\s+QUIT(\s+.*)?/i)
    @irc.close
  end

  def add_msg_hook(pattern, help = nil, &block)
    @msg_hooks << [pattern, help, block]
  end

  def add_join_hook(&block)
    @join_hooks << block
  end

  def add_leave_hook(&block)
    @leave_hooks << block
  end

  def handle_msg(who, where, msg)
    # don't react to self
    return if who == @nick
    # check for private conversation
    query = where == @nick
    where = who if query

    # prepare execution context for the command blocks
    stack = get_context_stack(:msg => msg, :where => where, :who => who, :query => query)
    stack.push_method(:say_chan, lambda { |msg| say(msg, where) }, self)

    @msg_hooks.each do |pattern, help, block|
      next unless msg =~ pattern
      begin
        stack.run_proc(block, *$~.captures)
      rescue Exception => e
        $stderr.puts "Error while executing command %s: %s" % [help, e.inspect]
        $stderr.puts e.backtrace
      end
    end
  end

  def handle_join(who, where)
    call_simple_hooks(@join_hooks, :who => who, :where => where)
  end

  def handle_leave(who, where, msg)
    call_simple_hooks(@leave_hooks, :who => who, :where => where, :msg => msg)
  end

  def call_simple_hooks(hooks, vars)
    stack = get_context_stack(vars)
    hooks.each { |block| stack.run_proc(block) }
  end

  def main_loop
    assert_connected
    loop do
      case get_line
      when /^:([^!]+)\S*\s+PRIVMSG\s+:?(#?\S+)\s+:?(.*)/i
        handle_msg(*$~.captures)
      when /^:([^!]+)\S*\s+JOIN\s+:?(#?\S+)\s+/i
        handle_join(*$~.captures)
      when /^:([^!]+)\S*\s+PART\s+:?(#?\S+)\s+:?(.*)/i
        handle_leave(*$~.captures)
      end
    end
  end

 protected

  def get_context_stack(hash)
    DynamicBinding::LookupStack.new.tap do |stack|
      stack.push_instance(self)
      stack.push_hash(hash)
    end
  end
end
