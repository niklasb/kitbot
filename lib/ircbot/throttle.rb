module IrcBot::Throttling
 protected

  def init_throttling(config = {})
    @config = {
      delay: 0.1,
      throttle_threshold_time: 2,
      throttle_threshold_messages: 5,
      throttle_factor: 10,
      throttle_time: 10,
    }.merge(config)

    @send_times = []
    @throttle_end = Time.now
  end

  def throttle
    sleep throttle_delay
  end

  def throttle_delay
    now = Time.now
    @send_times = @send_times.drop_while { |t|
      now - t > @config[:throttle_threshold_time]
    }
    if @send_times.size > @config[:throttle_threshold_messages]
      @throttle_end = now + @config[:throttle_time]
    end

    @config[:delay] * (now < @throttle_end ? @config[:throttle_factor] : 1)
  end
end
