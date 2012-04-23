require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'set'

class RssWatcher
  def initialize(urls, interval = 60, yield_initial = false)
    @urls       = urls
    @interval   = interval

    @seen_guids = Set.new
    @seen_guids |= items.map(&:guid).map(&:content) unless yield_initial
  end

  def get_rss(url)
    rss = RSS::Parser.parse(open(url) { |s| s.read }, false)
  end

  def items(&block)
    return enum_for(:items) unless block_given?
    @urls.each { |url| get_rss(url).items.each(&block) }
  end

  def run
    loop do
      items do |item|
        yield item if @seen_guids.add?(item.guid.content)
      end
      sleep(@interval)
    end
  end
end
