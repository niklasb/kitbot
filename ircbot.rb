require 'socket'
require 'test/unit/assertions'
require 'set'
require 'dynamic_binding'

class IrcError < Exception ; end

class IrcBot
  include Test::Unit::Assertions

  @cmds = %w{ join kick mode nick notice ping pong privmsg quit user }

  def initialize(nick)
    @nick = nick
    @conn = nil

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
    puts "--> %s" % msg
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
    line = decode(@conn.readline)

    line = line.strip
    puts line

    if handle_line(line)
      # line was already handled
      # (we want to respond to PING transparently)
      get_line
    else
      line
    end
  end

  def handle_line(line)
    case line
    when /^PING :(.+)$/i
      puts "[ Server ping ]"
      cmd_pong $1
    when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]PING (.+)[\001]$/i
      puts "[ CTCP PING from #{$1}!#{$2}@#{$3} ]"
      cmd_notice $1, "\001PING #{$4}\001"
    when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]VERSION[\001]$/i
      puts "[ CTCP VERSION from #{$1}!#{$2}@#{$3} ]"
      cmd_notice $1, "\001VERSION botbot\001"
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
    if args.any? { |a| a =~ /\s/ }
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

  def say(msg, target)
    raise ArgumentError, "No target given" if !target
    cmd_privmsg target, msg
  end

  def connect(server, port=6667)
    @conn = TCPSocket.open(server, port)
    cmd_user *["blah"]*4
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
      rescue => e
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
