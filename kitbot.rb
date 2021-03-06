require 'rubygems'
require 'bundler/setup'

require 'mechanize'
require 'yaml'
require 'pry'
require 'sequel'
require 'uri'
require 'thin'
require 'eventmachine'

$: << File.expand_path('../lib', __FILE__)

require 'feedwatch'
require 'ircbot'
require 'ircbot/api'
require 'mensa'
require 'slack'

unless ARGV.size == 1
  $stderr.puts "Usage: #{$0} config_file"
  exit 1
end
$config = File.open(ARGV[0]) { |f| YAML::load(f) }
bot = IrcBot::Bot.new($config['nick'])

# set up DB
$db = db = Sequel.connect($config['database'])
Sequel.extension :migration
Sequel::Migrator.run(db, File.expand_path('../db/migrations', __FILE__))

stats = db[:stats]
messages = db[:messages]
aliases = db[:aliases]

def format_time(datetime)
  datetime.strftime(datetime.is_a?(Date) ? $config['date_format']
                                         : $config['time_format'])
end

$feeds = [
  { channels: $config['channels'],
    url: 'http://seatping.kitinfo.de/?rss',
    formatter: lambda { 'Seatping alert! %s checked in: %s' % [author, url] } },
]

$slack = SlackApi.new($config['slack_api_token'])

# log
bot.add_fancy_msg_hook // do
  messages.insert(channel: where, user: who, time: Time.now, message: msg)

  # update user stats
  unless msg =~ /^\./
    words = msg.split.size
    chars = msg.size

    user = who
    if item = aliases.where(alias: user).first
      user = item[:user]
    end

    key = {channel: where, user: user, date: Date.today}
    rec = stats.where(*key)
    if 1 != rec.update(characters: Sequel.expr(:characters) + chars,
                       words: Sequel.expr(:words) + words)
      stats.insert(key.merge({ characters: chars, words: words }))
    end
  end
end

# User commands
#========================

# highscore link
bot.add_fancy_msg_hook /^\.statslink$/, '.statslink' do
  if query
    say_chan 'No links to stats in private channel'
  else
    say_chan "#{$config['stats_url'] % URI::escape(where[1..-1])} - #{where} Stats"
  end
end

# pastie link
bot.add_fancy_msg_hook /^\.paste$/, '.paste' do
  say_chan "Paste it at https://gist.github.com/ or http://pastie.org/"
end

# highscore by letter count
bot.add_fancy_msg_hook /^\.stats(?:\s+(\S+))?$/, '.stats' do |chan|
  chan ||= where
  top = stats.filter(channel: chan)
             .group(:user)
             .select { [user, sum(characters).as("total")] }
             .order(:total)
             .last($config['top_users'])
  str = top.map { |rec| "%s (%d)" % rec.values_at(:user, :total) }.join(", ")
  say_chan "Top users (letter count-wise): %s" % str
end

# single user stats
bot.add_fancy_msg_hook /^\.seen(?:\s+(\S+))?$/, '.seen' do |query|
  query ||= ''
  result = messages.filter(:user.like("%#{query}%"),
                           channel: where)
                   .exclude(:message.like(".%"))
                   .order(:time).last
  if result
    say_chan "Last seen at %s: <%s> %s" % [format_time(result[:time]),
                                           result[:user],
                                           result[:message]]
  else
    say_chan "Nope :("
  end
end

# show source
bot.add_fancy_msg_hook /^\.source$/, '.source' do
  say_chan 'My home: ' + $config['source_url']
end

# show feeds subscribed in this channel
bot.add_fancy_msg_hook /^\.feeds/, '.feeds' do
  say_chan "Feeds: " + $feeds.select { |f| f[:channels].include?(where) }
                             .map { |f| f[:url] }.join(", ")
end

answers = ['No.', 'Yes.', 'Bitch pls.']
bot.add_fancy_msg_hook /^\.8ball\s/, '.8ball' do
  say_chan 'The Magic 8 Ball says: %s' % answers.sample
end

# fetch Mensa menu
menu = Mensa::Menu.new
bot.add_fancy_msg_hook /^\.mensa(?:\s+(.*))?$/, '.mensa' do |args|
  args = args ? args.split : []
  day = Date.today

  # a numeric argument at the beginning specifies a day shift
  day += args.shift.to_i if args.size > 0 && args[0] =~ /^\d+$/

  begin
    lines = menu[day]
  rescue => e
    $stderr.puts 'Error while fetching mensa data: %s' % e.inspect
    $stderr.puts e.backtrace
    next
  end

  if !lines
    say_chan "No data for %s, sorry." % format_time(day)
    next
  end

  queries = args.empty? ? ["l"] : args
  say_chan "Menu for %s" % format_time(day)
  lines.each do |line, meals|
    next unless queries.any? { |query| line =~ /^#{query}/i }
    interesting_meals = meals.select { |_, price, _| price >= 110 }
    next if interesting_meals.empty?
    say_chan "%s: %s" % [line, interesting_meals.map { |name, price, price_note|
                              "%s (%s%.2f)" % [name,
                                                price_note ? price_note + ' ' : '',
                                                price/100.0] }.join(", ")]
  end
end

# seatping shortcut
locations = { 'audimax' => 1, 'gerthsen' => 2, 'hsaf' => 3 }
seatping_url = 'http://dev.cbcdn.com/seatping/?last=90&hall=%s'
bot.add_fancy_msg_hook /^\.sp(\s.*)?/, '.sp' do |loc|
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
bot.add_fancy_msg_hook %r{(https?://\S+)}, 'HTTP URLs (will fetch title)' do |url|
  begin
    page = agent.get(url)
    title = page.at('title').text.gsub(/\s+/, ' ').strip
  rescue => e
    $stderr.puts 'Error while fetching title of %s: %s' % [url, e.inspect]
    $stderr.puts e.backtrace
    next
  end

  say_chan "Title: %s" % title
end

# enable use of s/foo/bar syntax to correct mistakes
bot.add_fancy_msg_hook %r{^s/([^/]*)/([^/]*)/?$}, 's/x/y/ substitution' do |pattern, subst|
  begin
    pattern = Regexp.new(pattern)
  rescue
  else
    result = messages.filter(channel: where)
                    .exclude(:message.like("s/%"))
                    .order(:time)
                    .last(20)
                    .find { |rec| rec[:message] =~ pattern }
    next unless result

    say_chan "<%s> %s" % [result[:user],
                          result[:message].gsub(pattern, subst)]
  end
end

# irc -> slack
bot.add_fancy_msg_hook /^\.slack\s+(.*)?$/, '.stats' do |msg|
  $slack.post_message(msg, $config['slack_forward_channel'], $config['slack_username'])
end

# Control commands
#=====================

def join_stats_users(stats, a, b)
  stats.where(user: b).each do |item|
    other = stats.where(user: a, date: item[:date])
    if other.count > 0
      other.update(
          characters: Sequel.expr(:characters) + item[:characters], 
          words: Sequel.expr(:words) + item[:words])
    else
      stats.where(user: b, date: item[:date]).update(user: a)
    end
  end
  stats.where(user: b).delete
end

bot.add_fancy_msg_hook /^\.addalias\s+(\S+)\s+(\S.+)$/, 'add nick aliases' do |user, names|
  if $config['masters'].include?(who)
    names.split.each do |alias_|
      next if alias_ == user
      results = aliases.where(alias: alias_)
      if results.count > 0
        results.update(alias: alias_, user: user)
      else
        aliases.insert(alias: alias_, user: user)
      end
      join_stats_users(stats, user, alias_)
    end
    say_chan 'Aliases created successfully'
  else
    say_chan 'This command is only available to important people'
  end
end

Thread.abort_on_exception = true

# add webhooks
IrcBot::Webhooks.new(bot, db).register

EM.run do
  # start bot in background
  bot.start($config['server'], $config['port'], $config['use_ssl'])
  $config['channels'].each { |chan| bot.join(*chan) }
 
  # slack -> irc bridge
  ws = $slack.rtm

  ws.onopen do
    puts "Connected to Slack RTM API"
  end

  ws.onmessage do |msg, type|
    msg = JSON.parse(msg)
    if msg['type'] == 'message'
      slack_chan = $slack.channel_info(msg['channel'])      
      if slack_chan['ok'] != false 
        $config['channels'].each do |chan|
          user = $slack.user_info(msg['user'])['user']
          if user
            bot.say '#%s <%s> %s' % [slack_chan['channel']['name'], user ? user['name'] : '???', msg['text']], chan[0]
          end
        end
      end
    end
  end

  ws.onclose do |code, reason|
    $stderr.puts "Disconnected with status code: #{code}"
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
      rescue => e
        $stderr.puts "Exception in feed thread: %s" % e.inspect
        $stderr.puts e.backtrace
      end
    end
  end

  # start API server in background
  Thread.new do
    Thin::Server.start($config['api_host'], $config['api_port'],
                      IrcBot::WebRPC.new(bot, db))
  end

  Thread.new do
    # start an interactive shell
    binding.pry
    exit
  end
end
