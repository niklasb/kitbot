$: << File.expand_path('..', __FILE__)

require 'ircbot'
require 'open-uri'
require 'mechanize'
require 'yaml'
require 'pry'
require 'twitter'
require 'feedwatch'

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
$channels = ["#niklasbottest"]
$feeds = [
  { :channels => $channels,
    :url => 'http://dev.cbcdn.com/seatping/?rss',
    :formatter => lambda { 'Seatping alert! %s checked in: %s' % [author, url] } },
  { :channels => $channels,
    :url => 'http://www.heise.de/newsticker/heise-atom.xml',
    :formatter => lambda { 'Heise: %s -- %s' % [title, url] } },
]

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
  unless msg =~ /^\./
    stats[:letter_count] += msg.size
    stats[:last_msg] = msg
    stats[:last_seen] = Time.now
  end
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

# show feeds subscribed in this channel
bot.add_msg_hook /^\.feeds/, '.feeds' do
  say_chan "Feeds: " + $feeds.select { |f| f[:channels].include?(where) }
                             .map { |f| f[:url] }.join(", ")
end

# say bye :)
farewells = ["Don't forget to close the door behind you.",
             "One down, more to go.",
             "Aww, what a pity.",
            ]
bot.add_msg_hook /^\.bye$/, '.bye' do
  cmd_kick where, who, farewells.sample
end

answers = ['No.', 'Yes.', 'Bitch pls.']
bot.add_msg_hook /^\.8ball\s/, '.8ball' do
  say_chan 'The Magic 8 Ball says: %s' % answers.sample
end

# fetch Mensa menu
bot.add_msg_hook /^\.mensa$/, '.mensa' do
  items = Twitter.user_timeline("Mensa_KIT").take_while { |x| x.created_at > Date.today.to_time }
  if items.empty?
    say_chan "Not today."
  else
    say_chan items.map(&:text).reject { |text| text =~ /folgt jetzt/ }.join('; ')
  end
end

# seatping shortcut
locations = { 'audimax' => 1, 'gerthsen' => 2, 'hsaf' => 3 }
seatping_url = 'http://dev.cbcdn.com/seatping/?last=90&hall=%s'
bot.add_msg_hook /^\.sp(\s.*)?/, '.sp' do |loc|
  loc &&= locations[loc.strip.downcase]
  if loc
    say_chan seatping_url % loc
  else
    say_chan locations.map { |hall, id| '%s: %s' % [hall.capitalize, seatping_url % id] }.join(' ')
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

# start feed watchers in background
$feeds.each do |config|
  Thread.new do
    begin
      FeedWatcher.new([config[:url]], config[:interval] || 60).run do |entry|
        msg = entry.instance_exec(&config[:formatter])
        config[:channels].each do |chan|
          bot.say msg, chan
        end
      end
    rescue Exception => e
      $stderr.puts "Exception in feed thread: %s" % e.inspect
      $stderr.puts e.backtrace
    end
  end
end

# start bot in background
Thread.new do
  bot.connect($server)
  $channels.each { |chan| bot.join(chan) }
  bot.main_loop
end

# start an interactive shell in the main thread :)
binding.pry
