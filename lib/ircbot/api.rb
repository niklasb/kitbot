require 'sinatra'
require 'sinatra/namespace'
require 'sinatra-miniauth'
require 'json'
require 'digest'
require 'eventmachine'
require 'net/http'
require 'uri'

module IrcBot

class Webhooks
  MAX_FAILS = 5

  def initialize(bot, db)
    @bot = bot
    @hooks = db[:webhooks]
    @queue = []
  end

  def register
    hooks = @hooks
    @bot.add_msg_hook // do
      hooks.where(hook: 'message').all
           .select { |hook| where == hook[:channel] &&
                            !query &&
                            msg =~ Regexp.new(hook[:argument]) }.each do |hook|
        rec = hooks.where(id: hook[:id])
        EventMachine.defer do
          begin
            Net::HTTP.post_form(URI.parse(hook[:url]), 'message' => msg,
                                                       'channel' => where)
            rec.update(fails: 0)
          rescue
            if hook[:fails] > MAX_FAILS
              rec.delete
            else
              rec.update(:fails => :fails + 1)
            end
          end
        end
      end
    end
  end
end

class WebRPC < Sinatra::Base
  include Sinatra::MinimalAuthentication
  register Sinatra::Namespace

  def initialize(bot, db)
    super()
    @bot = bot
    @api_users = db[:api_users]
    @webhooks = db[:webhooks]
    @messages = db[:messages]

    init_auth "Web API" do |user, password|
      hash = Digest::SHA1.hexdigest(password)
      @api_users.where(user: user, password: hash).first
    end
  end

  namespace %r{/channel/(?:[^/]+)} do
    before do
      @channel = '#' + request.fullpath.split('/')[2]
      authorize!
    end

    get '/users' do
      json @bot.get_users(@channel)
    end

    get '/usercount' do
      json @bot.get_users(@channel).size
    end

    get '/topic' do
      json @bot.get_topic(@channel)
    end

    get '/messages/last' do
      json @messages.where(channel: @channel).order(:time).last
    end

    post '/messages' do
      @bot.say params[:text], @channel
      json true
    end

    get '/hooks/message' do
      json @webhooks.where(user: user, channel: @channel).map { |hook|
        { id: hook[:id], url: hook[:url], pattern: hook[:argument] }
      }
    end

    post '/hooks/message' do
      id = @webhooks.insert(url: params[:url], channel: @channel,
                            hook: 'message', argument: params[:pattern] || '',
                            user: user)
      json id
    end

    delete '/hooks/message/:id' do |id|
      rec = @webhooks.where(id: id.to_i)
      halt 403, "Access denied" if rec.first && user != rec.first[:user]
      json (rec.delete > 0 ? true : false)
    end
  end

 protected

  def json(obj)
    content_type :json
    obj.to_json
  end
end

end
