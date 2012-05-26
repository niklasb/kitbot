require 'dynamic_binding'

module IrcBot::Hooks
  def add_msg_hook(pattern, help = nil, &block)
    @msg_hooks << [pattern, help, block]
  end

  def add_join_hook(&block) @join_hooks << block end
  def add_part_hook(&block) @part_hooks << block end

 protected

  def init_hooks
    @msg_hooks, @join_hooks, @part_hooks = [], [], []

    push_handler /^:([^!]+)\S* PRIVMSG :?(#?\S+) :?(.*)/, &method(:handle_msg)
    push_handler /^:([^!]+)\S* JOIN :?(#?\S+)/,           &method(:handle_join)
    push_handler /^:([^!]+)\S* PART :?(#?\S+) :?(.*)/,    &method(:handle_part)

    m = @msg_hooks
    add_msg_hook /^\.help$/, '.help' do
      say_chan 'I understand: %s' % m.map { |_,h,_| h }
                                     .reject(&:nil?).join(', ')
    end
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
        $stderr.puts 'Error while executing command %s: %s' % [help, e.inspect]
        $stderr.puts e.backtrace
      end
    end
  end

  def handle_join(who, where)
    call_simple_hooks(@join_hooks, :who => who, :where => where)
  end

  def handle_part(who, where, msg)
    call_simple_hooks(@part_hooks, :who => who, :where => where, :msg => msg)
  end

  def call_simple_hooks(hooks, vars)
    stack = get_context_stack(vars)
    hooks.each { |block| stack.run_proc(block) }
  end

  def get_context_stack(hash)
    DynamicBinding::LookupStack.new.tap do |stack|
      stack.push_instance(self)
      stack.push_hash(hash)
    end
  end
end
