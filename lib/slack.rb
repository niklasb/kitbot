require 'json'
require 'mechanize'
require 'websocket-eventmachine-client'

class SlackApi
  def initialize(token)
    @token = token
    @channel_cache = {}
    @user_cache = {}
  end

  def api(cmd, args={})
    args = args.merge({'token' => @token})
    JSON.parse(Mechanize.new.post('https://slack.com/api/%s' % cmd, args).body)
  end
  
  def channel_info(channel_id)
    @channel_cache[channel_id] ||= api('channels.info', {
      'channel' => channel_id
    })
    @channel_cache[channel_id]
  end
  
  def user_info(user_id)
    @user_cache[user_id] ||= api('users.info', {
      'user' => user_id
    })
    @user_cache[user_id]
  end

  def post_message(msg, chan, username)
    api('chat.postMessage', {
      'channel' => chan,
      'username' => username,
      'text' => msg,
    })
  end

  def rtm
    url = api('rtm.start')['url']
    p url
    WebSocket::EventMachine::Client.connect(:uri => url)
  end
end 
