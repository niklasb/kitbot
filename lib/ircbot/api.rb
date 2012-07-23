require 'sinatra'
require 'sinatra/namespace'
require 'sinatra-miniauth'
require 'sinatra-async'
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
    @bot.add_msg_hook // do |ctx|
      get_matching_hooks('message', ctx.where, ctx.query)
               .select { |hook| ctx.msg =~ Regexp.new(hook[:argument]) }.each do |hook|
        call_webhook(hook, message: ctx.msg, channel: ctx.where, user: ctx.who)
      end
    end

    @bot.add_join_hook do |ctx|
      get_matching_hooks('join', ctx.where, ctx.query).each do |hook|
        is_bot = (ctx.who == @bot.nick)
        call_webhook(hook, channel: ctx.where, user: ctx.who, bot: is_bot ? 1 : 0)
      end
    end

    @bot.add_part_hook do |ctx|
      get_matching_hooks('part', ctx.where, ctx.query).each do |hook|
        call_webhook(hook, channel: ctx.where, user: ctx.who, message: ctx.msg)
      end
    end

    @bot.add_topic_hook do |ctx|
      get_matching_hooks('topic', ctx.where, false).each do |hook|
        call_webhook(hook, channel: ctx.where, user: ctx.who, topic: ctx.topic)
      end
    end

    @bot.add_quit_hook do |ctx|
      @hooks.where(hook: 'quit').all do |hook|
        call_webhook(hook, user: ctx.who, message: ctx.msg)
      end
    end
  end

 protected

  def call_webhook(hook, args)
    EventMachine.defer do
      rec = @hooks.where(id: hook[:id])
      begin
        Net::HTTP.post_form(URI.parse(hook[:url]), args.merge(hook: hook[:hook]))
      rescue
        if hook[:fails] > MAX_FAILS
          rec.delete
        else
          rec.update(:fails => :fails + 1)
        end
      else
        rec.update(fails: 0)
      end
    end
  end

  def get_matching_hooks(type, channel, query)
    # no hooks for private channels
    return [] if query
    @hooks.where(hook: type).all.select { |hook| hook[:channel] == channel }
  end
end

class WebRPC < Sinatra::Base
  include Sinatra::AsyncRequests
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

  before do
    authorize!
  end

  namespace %r{/user/(?:[^/]+)} do
    before do
      @user = request.fullpath.split('/')[2]
    end

    post '/messages' do
      @bot.say params[:text], @user
      json true
    end
  end

  namespace %r{/channel/(?:[^/]+)} do
    before do
      @channel = '#' + request.fullpath.split('/')[2]
    end

    get '/users' do
      json @bot.get_users(@channel)
    end

    get '/users/count' do
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

    post '/hooks/:type' do |type|
      halt 404, "Invalid hook type" unless ['message', 'join', 'part', 'topic'].include?(type)

      argument = case type
                 when 'message' then params[:pattern] || ''
                 else ''
                 end

      id = @webhooks.insert(url: params[:url], channel: @channel, hook: type,
                            argument: argument, user: user)
      json id
    end
  end

  post '/hooks/quit' do
    id = @webhooks.insert(hook: 'quit', url: params[:url], user: user,
                          channel: '', argument: '')
    json id
  end

  get '/hooks' do
    json @webhooks.where(user: user).map { |hook|
      additional = case hook[:hook]
                   when 'message' then { pattern: hook[:argument] }
                   else {}
                   end
      { id: hook[:id],
        channel: hook[:channel],
        type: hook[:hook],
        url: hook[:url]
      }.merge(additional)
    }
  end

  delete '/hooks/:id' do |id|
    rec = @webhooks.where(id: id.to_i)
    halt 403, "Access denied" if rec.first && user != rec.first[:user]
    json (rec.delete > 0)
  end

 protected

  def json(obj)
    content_type :json
    obj.to_json + "\n"
  end
end

end
