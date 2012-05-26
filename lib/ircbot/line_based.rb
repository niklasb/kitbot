require 'syncutils'

module IrcBot::LineBasedProtocol
 protected

  def handle_line(line)
    @handlers.reverse_each do |handler, pattern|
      if pattern
        handler.call(*$~.captures) if line =~ pattern
      else
        handler.call(line)
      end
    end
  end

  def push_handler(pattern = nil, &block)
    value = [block, pattern]
    handlers = (@handlers ||= [])
    handlers.push(value)
    Object.new.tap do |ret|
      (class << ret; self; end).send(:define_method, :remove) do
        handlers.delete(value)
      end
    end
  end

  def wait_for_line(pattern)
    SyncUtils.await do |ev|
      h = push_handler(pattern) { |*args|
        h.remove
        ev.signal
      }
      yield if block_given?
    end
  end

  def get_line
    line = decode(@conn.readline).strip
    puts '< ' + line
    line
  end

  def send(msg)
    assert_connected
    puts '> ' + msg
    @conn.send msg + "\r\n", 0
  end

  def decode(str)
    str = str.dup
    ['utf-8', 'iso-8859-1'].each do |enc|
      str.force_encoding enc
      return str if str.valid_encoding?
    end
    return str.encode('ascii', :invalid => :replace, :undef => :replace, :replace => '')
  end
end
