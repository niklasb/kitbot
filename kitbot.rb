$: << File.expand_path('..', __FILE__)

require 'ircbot'
require 'open-uri'
require 'mechanize'

MAX_HISTORY = 20

bot = IrcBot.new("Kitbot")

bot.add_command /^.time$/, '.time' do |bot, where, from|
  bot.say "Time: %s" % Time.now, where
end

agent = Mechanize.new
bot.add_command /(https?:\/\/\S+)/, 'HTTP URLs (will fetch title)' do |bot, where, from, url|
  page = agent.get(url)
  title = page.at('title').text.gsub(/\s+/, ' ').strip
  bot.say "Title: %s" % title, where
end

# implement logging, as the substitution mechanism depends on it :)
history = Hash.new { |h,k| h[k] = [] }

bot.add_command /(.*)/ do |bot, where, from, msg|
  chanhist = history[where]
  chanhist << [Time.now, from, msg]
  history[where] = chanhist[-MAX_HISTORY..-1] if chanhist.size > MAX_HISTORY
end

bot.add_command /^s?\/([^\/]*)\/([^\/]*)\/?$/, 's/x/y/ substitution' do |bot, where, from, pattern, subst|
  pattern = Regexp.new(pattern)
  time, from, msg = history[where].reverse.drop(1).find { |_, _, m| m =~ pattern }
  bot.say "<%s> %s" % [from, msg.gsub(pattern, subst)], where
end

bot.connect("irc.freenode.org")
bot.join("#kitinfo")
bot.main_loop
