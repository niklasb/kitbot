require 'eventmachine'
require 'ostruct'
require 'dynamic_binding'

module IrcBot::Hooks
  def add_msg_hook(pattern, help = nil, &block)
    @msg_hooks << [pattern, help, block]
  end

  def add_join_hook(&block)  @join_hooks << block end
  def add_part_hook(&block)  @part_hooks << block end
  def add_quit_hook(&block)  @quit_hooks << block end
  def add_topic_hook(&block) @topic_hooks << block end

  def add_fancy_msg_hook(*args, &block)
    add_msg_hook(*args) do |ctx|
      stack = get_context_stack(msg: ctx.msg,
                                where: ctx.where,
                                who: ctx.who,
                                query: ctx.query)
      stack.push_method(:say_chan, lambda { |msg| say(msg, ctx.where) }, self)
      stack.run_proc(block, *ctx.captures)
    end
  end

 protected

  def init_hooks
    @msg_hooks, @join_hooks, @part_hooks, @quit_hooks, @topic_hooks = 5.times.map { [] }

    push_handler /^:([^!]+)\S* PRIVMSG :?(\S+) :?(.*)/,   &method(:handle_msg)
    push_handler /^:([^!]+)\S* JOIN :?(\S+)/,             &method(:handle_join)
    push_handler /^:([^!]+)\S* PART :?(\S+)(?: :?(.*))?/, &method(:handle_part)
    push_handler /^:([^!]+)\S* QUIT(?: :?(.*))?/,         &method(:handle_quit)
    push_handler /^:([^!]+)\S* TOPIC :?(\S+) :?(.*)/,     &method(:handle_topic)

    add_msg_hook /^\.help$/, '.help' do |ctx|
      say 'I understand: %s' % @msg_hooks.map { |_,h,_| h }.reject(&:nil?).join(', '),
          ctx.where
    end
  end

  def handle_msg(who, where, msg)
    # don't react to self
    return if who == @nick
    # check for private conversation
    query = where == @nick
    where = who if query

    ctx_template = { who: who, where: where, query: query, msg: msg }

    @msg_hooks.each do |pattern, help, block|
      next unless msg =~ pattern
      ctx = OpenStruct.new(ctx_template.merge(captures: $~.captures))
      EventMachine.defer { block.call(ctx) }
    end
  end

  def handle_join(who, where)
    call_simple_hooks(@join_hooks, who: who, where: where, query: where == @nick)
  end

  def handle_part(who, where, msg)
    call_simple_hooks(@part_hooks, who: who, where: where,
                                   query: where == @nick, msg: msg)
  end

  def handle_topic(who, where, topic)
    call_simple_hooks(@topic_hooks, who: who, where: where, topic: topic)
  end

  def handle_quit(who, msg)
    call_simple_hooks(@quit_hooks, who: who, msg: msg)
  end

  def call_simple_hooks(hooks, vars)
    ctx = OpenStruct.new(vars)
    hooks.each { |block| block.call(ctx) }
  end

  def get_context_stack(hash)
    DynamicBinding::LookupStack.new.tap do |stack|
      stack.push_instance(self)
      stack.push_hash(hash)
    end
  end
end
