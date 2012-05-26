require 'monitor'

module SyncUtils
  def self.await
    ev = Event.new
    yield ev
    ev.wait
  end

  class Event
    def initialize
      @mutex = Monitor.new
      @mutex.synchronize { @cv = @mutex.new_cond }
    end

    def wait
      @mutex.synchronize { @cv.wait }
    end

    def signal
      @mutex.synchronize { @cv.signal }
    end
  end
end
