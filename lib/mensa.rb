require 'nokogiri'
require 'open-uri'

module Mensa
  StudentenwerkUri = 'http://www.studentenwerk-karlsruhe.de/de/essen/?view=ok&STYLE=popup_plain&c=adenauerring&p=1'

  class Menu
    def update(day)
      @data = StudentenwerkScraper.new.data unless @data && @data.include?(day)
    end

    def [](day)
      update(day)
      @data[day]
    end
  end

  class StudentenwerkScraper
    def initialize(html=nil)
      html ||= open(StudentenwerkUri) { |s| s.read }
      @doc = Nokogiri::HTML.parse(html)
    end

    def data
      tables = @doc.css("#platocontent > table")
      captions = tables.map { |t| t.xpath("preceding::h1").last.text }
      dates = captions.map { |c| Date.strptime(c.split.last, "%d.%m.") }
      menus = tables.map { |t| parse_day_table(t) }
      Hash[dates.zip(menus)]
    end

    def parse_day_table(table)
      Hash[table.xpath('./tr').map(&:children)
                .select { |children| !children.empty? }
                .map { |left, right| [left.text.gsub('Linie ', 'L'),
                                      parse_line_table(right)] }
#          .reject { |_, meals| meals.empty? }
          ]
    end

    def parse_line_table(table)
      table.css('tr').map{ |x| x.css('td') }
                     .select { |_, left, right| left && right && left.at_css('.bg') && right.at_css('.bg') }
                     .map { |_, left, right|
        meal = normalize_whitespace(left.at_css('.bg').text)
        price = right.at_css('.bg').text.strip
        price = price.empty? ? 0 : price.split[0].gsub(',','').to_i
        [meal, price]
      }
    end

    def normalize_whitespace(text)
      text.strip.gsub(/\s+/, ' ')
    end
  end
end
