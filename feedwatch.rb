require 'feedzirra'
require 'set'

class FeedWatcher
  def initialize(urls, interval = 60, yield_initial = false)
    @urls       = urls
    @interval   = interval

    @seen_ids = Set.new
    @seen_ids |= entries.map(&:id) unless yield_initial
  end

  def parse_feed(url)
    Feedzirra::Feed.fetch_and_parse(url)
  end

  def entries(&block)
    return enum_for(:entries) unless block_given?
    @urls.each { |url| parse_feed(url).entries.each(&block) }
  end

  def run
    loop do
      entries do |entry|
        yield entry if @seen_ids.add?(entry.id)
      end
      sleep(@interval)
    end
  end
end
