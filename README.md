### Overview

A simple IRC bot written in Ruby to watch over #kitinfo :)

The general IRC logic is hidden in `ircbot.rb`, the specific commands of the bot 
are defined in `kitbot.rb`.

### Running

You will need to install the dependencies first. I recommend using [RVM](https://rvm.io/)
to get a recent Ruby.

Using [Bundler](http://gembundler.com/), we can then easily install the dependencies:

    $ bundle install

And run the bot:

    $ ruby kitbot.rb
