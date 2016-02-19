require 'feedjira'
require 'set'

class FeedError < Exception; end

class FeedWatcher
  def initialize(urls, interval = 60, yield_initial = false)
    @urls       = urls
    @interval   = interval

    @seen_ids = Set.new
    @seen_ids |= entries.map(&:id) unless yield_initial
  end

  def parse_feed(url)
    Feedjira::Feed.fetch_and_parse(url).tap do |res|
      raise FeedError, "Invalid response" if res.is_a?(Fixnum)
    end
  end

  def entries(&block)
    return enum_for(:entries) unless block_given?
    @urls.each { |url| parse_feed(url).entries.each(&block) }
  end

  def run
    loop do
      begin
        entries do |entry|
          yield entry if @seen_ids.add?(entry.id)
        end
      rescue FeedError
      end
      sleep(@interval)
    end
  end
end
