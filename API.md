## Web RPC

The web service is secured by HTTP basic authentication. All responses are
[JSON](http://www.json.org) encoded.

### Commands

---

    GET /channel/:channel/users

List of users in the given channel:

    $ curl --user user:pass http://bot.kitinfo.de:1337/channel/kitinfo/users
    ["cbdev", "niklasb"]

---

    GET /channel/:channel/users/count

Number of users in the given channel:

    $ curl --user user:pass http://bot.kitinfo.de:1337/channel/kitinfo/usercount
    24

---

    GET /channel/:channel/topic

Gets the topic of the given channel. Returns `null` if channel doesn't exist and the
empty string if the channel has no topic set:

    $ curl --user user:pass http://bot.kitinfo.de:1337/channel/kitinfo/topic
    "... http://kitinfo.de/"
    $ curl --user user:pass http://bot.kitinfo.de:1337/channel/notexisting/topic
    null

---

    GET /channel/:channel/messages/last

Gets the last message sent in the given channel:

    $ curl --user user:pass http://bot.kitinfo.de:1337/channel/kitinfo/messages/last
    {"channel":"#kitinfo","user":"niklasb","time":"2012-05-30T18:18:13+02:00",
     "message":"wait for it"}

---

    POST /channel/:channel/messages

Say something in the given channel. The `text` POST parameter is used as the message:

    $ curl --user user:pass -d text=bla \
                  http://bot.kitinfo.de:1337/channel/kitinfo/messages

### Webhooks

You can register a webhook (HTTP callback) for certain events in a channel:

* `message`: Triggered if a message is sent.
* `join`: Triggered if a user joins or if the bot enters the channel for the
  first time
* `part`: Triggered if a user leaves the channel
* `topic`: Triggered if the topic is changed
* `quit`: Triggered if a user leaves the server

All of the following commands require an `url` argument: The URL to `POST` to if the
event occurs. Some also take other arguments, as described below.

The return value of the command is the ID of the inserted hook. It can be used
to delete the hook later on.

---

    POST /channel/:channel/hooks/message

Add a hook that is triggered if a message is sent in the channel. The
optional `pattern` parameter can be used to define a regular expression to
match incoming messages against. Only for matching messages, the hook will be
triggered:

    # will register a hook on every message
    curl --user user:pass -d url=http://my/callback.php \
              http://bot.kitinfo.de:1337/channel/kitinfo/hooks/message

    # will register a hook that is only triggered for messages starting with
    # the string `.somecommand`
    curl --user user:pass -d 'url=http://my/callback.php&pattern=%5E%5C.somestring' \
              http://bot.kitinfo.de:1337/channel/kitinfo/hooks/message

The `POST` request triggered if a message is sent will look something like

     POST http://my/callback.php

     user=[the user who sent the message]&message=[the message]
     &channel=#kitinfo&hook=message

---

    POST /channel/:channel/hooks/join

Add a hook that is triggered if a user or the bot joins a channel:

    curl --user user:pass -d url=http://my/callback.php \
              http://bot.kitinfo.de:1337/channel/kitinfo/hooks/join

The `POST` request triggered if a message is sent will look something like

     POST http://my/callback.php

     user=[the joined user]&bot=0&channel=#kitinfo&hook=join

where the value of the `bot` argument (`0` or `1`) determines if the joined user is
the bot itself.

---

    POST /channel/:channel/hooks/part

Add a hook that is triggered if a user leaves a channel:

    curl --user user:pass -d url=http://my/callback.php \
              http://bot.kitinfo.de:1337/channel/kitinfo/hooks/part

The `POST` request triggered if a message is sent will look something like

     POST http://my/callback.php

     user=[the leaving user]&message=[the leave message]&channel=#kitinfo&hook=part

---

    POST /channel/:channel/hooks/topic

Add a hook that is triggered if the topic of a channel is changed:

    curl --user user:pass -d url=http://my/callback.php \
              http://bot.kitinfo.de:1337/channel/kitinfo/hooks/topic

The `POST` request triggered if a message is sent will look something like

     POST http://my/callback.php

     topic=[the new topic]&user=[user who changed it]&channel=#kitinfo&hook=topic

---

    POST /hooks/quit

Add a hook that is triggered if a user leaves the server:

    curl --user user:pass -d url=http://my/callback.php \
              http://bot.kitinfo.de:1337/hooks/quit

The `POST` request triggered if a message is sent will look something like

     POST http://my/callback.php

     user=[user who left]&message=[quit message]&hook=quit

#### Managing hooks

---

    GET /hooks

Gets a list of all registered hooks:

    $ curl --user user:pass http://bot.kitinfo.de:1337/hooks
    [{"id":2,"channel":"#kitinfo","type":"message","url":"http://my/callback.php",
      "pattern":""},
     {"id":3,"channel":"#kitinfo","type":"join","url":"http://my/callback.php"}]

---

    DELETE /hooks/:id

Deletes the hook with the given ID. Returns `true` on success and
`false` on failure:

    $ curl -X DELETE --user user:pass http://bot.kitinfo.de:1337/hooks/2
    true
