$: << File.expand_path('..', __FILE__)

require 'ircbot'
require 'open-uri'
require 'mechanize'
require 'yaml'
require 'pry'
require 'twitter'

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
(config[:user_stats] || {}).each do |chan,users|
  users.each do |user, stats|
    user_stats[chan][user].merge! stats
  end
end

# log
bot.add_msg_hook // do
  chanhist = history[where]
  chanhist << [Time.now, who, msg]

  # trim history to configured backlog size
  history[where] = chanhist[-$max_history..-1] if chanhist.size > $max_history

  # update user stats
  stats = user_stats[where][who]
  stats[:letter_count] += msg.size
  stats[:last_msg] = msg
  stats[:last_seen] = Time.now
end

# Commands
#========================

# highscore by letter count
bot.add_msg_hook /^\.stats$/, '.stats' do
  users_count = user_stats[where].map { |user, stats| [user, stats[:letter_count]] }
  top = users_count.sort_by { |user, count| -count }[0,$top_users]
  str = top.map { |x| "%s (%d)" % x }.join(", ")
  say_chan "Top users (letter count-wise): %s" % str
end

# single user stats
bot.add_msg_hook /^\.seen\s+(\S+)$/, '.seen' do |query|
  result = user_stats[where].find { |name, _| name.downcase.include?(query.downcase) }
  if result
    name, stats = result
    say_chan "Last seen at %s: <%s> %s" % [stats[:last_seen].strftime("%d.%m.%Y %H:%M"),
                                           name,
                                           stats[:last_msg]]
  else
    say_chan "Nope :("
  end
end

# show source
bot.add_msg_hook /^\.source$/, '.source' do
  say_chan 'My home: http://github.com/niklasb/kitbot'
end

# say bye :)
farewells = ["Don't forget to close the door behind you.",
             "One down, more to go.",
             "Aww, what a pity.",
            ]
bot.add_msg_hook /^\.bye$/, '.bye' do
  cmd_kick where, who, farewells.sample
end

# fetch Mensa menu
bot.add_msg_hook /^\.mensa$/, '.mensa' do
  items = Twitter.user_timeline("Mensa_KIT").take_while { |x| x.created_at > Date.today.to_time }
  if items.empty?
    say_chan "Not today."
  else
    say_chan items.map(&:text).reject { |text| text =~ /folgt jetzt/ }.join(', ')
  end
end

# fetch the title of pasted URLs
agent = Mechanize.new
agent.user_agent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0)"
bot.add_msg_hook /(https?:\/\/\S+)/, 'HTTP URLs (will fetch title)' do |url|
  page = agent.get(url)
  title = page.at('title').text.gsub(/\s+/, ' ').strip
  say_chan "Title: %s" % title
end

# enable use of s/foo/bar syntax to correct mistakes
bot.add_msg_hook /^s?\/([^\/]*)\/([^\/]*)\/?$/, 's/x/y/ substitution' do |pattern, subst|
  pattern = Regexp.new(pattern)
  result = history[where].reverse.drop(1).find { |_, w, m| w == who && m =~ pattern }
  if result
    time, who, msg = result
    say_chan "<%s> %s" % [who, msg.gsub(pattern, subst)]
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
