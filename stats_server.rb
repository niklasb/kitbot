require 'rubygems'
require 'bundler/setup'

require 'sequel'
require 'sinatra'
require 'haml'

unless ARGV.size == 1
  $stderr.puts "Usage: #{$0} config_file"
  exit 1
end
$config = File.open(ARGV[0]) { |f| YAML::load(f) }

# set up DB
db = Sequel.connect($config['database'])
stats = db[:stats]
messages = db[:messages]

def start_of_week
  Date.commercial(Date.today.year, Date.today.cweek, 1)
end

def start_of_month
  Date.civil(Date.today.year, Date.today.month, 1)
end

def start_of_year
  Date.new(Date.today.year)
end

get '/' do
  msgs = stats.filter(channel: params[:channel])

  @stats = [Date.today, start_of_week, start_of_month, nil].map { |start|
    filtered = start ? msgs.filter('date >= ?', start) : msgs
    grouped = filtered.group(:user)
    [grouped.select { [user, sum(characters).as('total')] },
     grouped.select { [user, sum(words).as('total')] }
    ].map { |result|
      result.having('total > 0').order(:total).reverse.all
    }
  }
  haml :index
end
