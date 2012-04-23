require 'nokogiri'
require 'open-uri'

module Mensa
  StudentenwerkUri = 'http://www.studentenwerk-karlsruhe.de/de/essen/?view=ok&STYLE=popup_plain&c=adenauerring&p=1'

  class StudentenwerkScraper
    def initialize(html=nil)
      html ||= open(StudentenwerkUri) { |s| s.read }
      @doc = Nokogiri::HTML.parse(html)
    end

    def data
      today = Date.today
      monday = today - today.wday + 1
      date_range = monday ... (monday + 5)
      menus = @doc.css("#platocontent > table").map { |t| parse_day_table(t) }
      Hash[date_range.zip(menus)]
    end

    def parse_day_table(table)
      Hash[table.xpath('./tr').map(&:children)
                .map { |left, right| [left.text.gsub('Linie ', 'L'),
                                      parse_line_table(right)] }
                .reject { |_, meals| meals.empty? }
          ]
    end

    def parse_line_table(table)
      table.css('tr').map(&:children)
                     .select { |left, right| left.at_css('.bg') && right.at_css('.bgp') }
                     .map { |left, right|
        meal = normalize_whitespace(left.at_css('.bg').text)
        price_fragment = right.at_css('.bgp').clone
        price_note = price_fragment.at_css('small')
        price_note &&= normalize_whitespace(price_note.remove.text)
        price = normalize_whitespace(price_fragment.text).gsub(',', '').to_i
        [meal, price, price_note]
      }
    end

    def normalize_whitespace(text)
      text.strip.gsub(/\s+/, ' ')
    end
  end
end
