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

$max_history = 100
$top_users = 5
$config_file = "config.yml"
$nick = "Kitbot"
$server = "irc.freenode.org"
$channels = ["#kitinfo"]

config = load_yaml_hash($config_file)
bot = IrcBot.new($nick)

# set up logging, as the substitution mechanism and stats depend on it :)
history = Hash.new { |h,k| h[k] = [] }
user_stats = Hash.new { |h,k| h[k] = Hash.new { |h,k| h[k] = { :letter_count => 0 }}}
# merge data from file
(config[:letters] || {}).each do |chan,users|
  users.each do |user, stats|
    user_stats[chan][user].merge! stats
  end
end

# log
bot.add_command /(.*)/ do |bot, where, from, msg|
  chanhist = history[where]
  chanhist << [Time.now, from, msg]

  # trim history to configured backlog size
  history[where] = chanhist[-$max_history..-1] if chanhist.size > $max_history

  # update user stats
  stats = user_stats[where][from]
  stats[:letter_count] += msg.size
  stats[:last_msg] = msg
  stats[:last_seen] = Time.now
end

# Commands
#========================

# highscore by letter count
bot.add_command /^.stats$/, '.stats' do |bot, where|
  users_count = user_stats[where].map { |user, stats| [user, stats[:letter_count]] }
  top = users_count.sort_by { |user, count| -count }[0..$top_users]
  str = top.map { |x| "%s (%d)" % x }.join(", ")
  bot.say "Top users (letter count-wise): %s" % str, where
end

# single user stats
bot.add_command /^.seen\s+(\S+)$/, '.seen' do |bot, where, from, query|
  result = user_stats[where].find { |name, _| name.include?(query) }
  if result
    name, stats = result
    bot.say "Last seen at %s: '<%s> %s'" % [stats[:last_seen].strftime("%Y/%m/%d %H:%M"),
                                            name,
                                            stats[:last_msg]], where
  else
    bot.say "Nope :(", where
  end
end

# fetch the title of pasted URLs
agent = Mechanize.new
agent.user_agent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0)"
bot.add_command /(https?:\/\/\S+)/, 'HTTP URLs (will fetch title)' do |bot, where, from, url|
  page = agent.get(url)
  title = page.at('title').text.gsub(/\s+/, ' ').strip
  bot.say "Title: %s" % title, where
end

# enable use of s/foo/bar syntax to correct mistakes
bot.add_command /^s?\/([^\/]*)\/([^\/]*)\/?$/, 's/x/y/ substitution' do |bot, where, from, pattern, subst|
  pattern = Regexp.new(pattern)
  result = history[where].reverse.drop(1).find { |_, f, m| f == from && m =~ pattern }
  if result
    time, from, msg = result
    bot.say "<%s> %s" % [from, msg.gsub(pattern, subst)], where
  end
end

# don't forget to write stats back to config
at_exit do
  open($config_file, 'wb') { |f| f.write({ :user_stats => user_stats }.to_yaml) }
end

# start bot in background
Thread.new(bot) do |bot|
  bot.connect($server)
  $channels.each { |chan| bot.join(chan) }
  bot.main_loop
end

# start an interactive shell in the main thread :)
binding.pry
