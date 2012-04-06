$: << File.expand_path('..', __FILE__)

require 'ircbot'
require 'open-uri'
require 'mechanize'
require 'yaml'
require 'pry'

def load_yaml_hash(fname)
  File.open(fname, 'rb') { |f| YAML::load(f) }
rescue
  {}
end

MAX_HISTORY = 100
TOP = 5
CONFIG_FILE = "config.yml"

config = load_yaml_hash(CONFIG_FILE)
bot = IrcBot.new("Kitbot")

bot.add_command /^.time$/, '.time' do |bot, where, from|
  bot.say "Time: %s" % Time.now, where
end

agent = Mechanize.new
agent.user_agent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0)"
bot.add_command /(https?:\/\/\S+)/, 'HTTP URLs (will fetch title)' do |bot, where, from, url|
  page = agent.get(url)
  title = page.at('title').text.gsub(/\s+/, ' ').strip
  bot.say "Title: %s" % title, where
end

# implement logging, as the substitution mechanism and stats depend on it :)
history = Hash.new { |h,k| h[k] = [] }
letters = Hash.new { |h,k| h[k] = Hash.new(0) }
(config[:letters] || {}).each do |chan,users|
  letters[chan].merge! users
end

bot.add_command /(.*)/ do |bot, where, from, msg|
  chanhist = history[where]
  chanhist << [Time.now, from, msg]
  history[where] = chanhist[-MAX_HISTORY..-1] if chanhist.size > MAX_HISTORY
  letters[where][from] += msg.size
end

bot.add_command /^.stats$/, '.stats' do |bot, where|
  top = letters[where].sort_by { |_, count| -count }[0..TOP]
  str = top.map { |x| "%s (%d)" % x }.join(", ")
  bot.say "Top users (letter count-wise): %s" % str, where
end

bot.add_command /^s?\/([^\/]*)\/([^\/]*)\/?$/, 's/x/y/ substitution' do |bot, where, from, pattern, subst|
  pattern = Regexp.new(pattern)
  result = history[where].reverse.drop(1).find { |_, f, m| f == from && m =~ pattern }
  if result
    time, from, msg = result
    bot.say "<%s> %s" % [from, msg.gsub(pattern, subst)], where
  end
end

Thread.new(bot) do |bot|
  bot.connect("irc.freenode.org")
  bot.join("#kitinfo")
  bot.main_loop
end

# interactive shell
binding.pry

# write data to config
open(CONFIG_FILE, 'wb') { |f| f.write({ :letters => letters }.to_yaml) }
