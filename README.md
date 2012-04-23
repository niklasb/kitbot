### Overview

A simple IRC bot written in Ruby to watch over #kitinfo :)

The general IRC logic is hidden in `ircbot.rb`, the specific commands of the bot 
are defined in `kitbot.rb`.

### Installing and running

You will need to install the dependencies first:

* Git
* Ruby and Rubygems. I recommend using [RVM](https://rvm.io/) to get a recent version
(the bot is not not tested with Ruby <= 1.9.3)
* [Bundler](http://gembundler.com/). This comes for free if you use RVM

We can then easily install the Gem dependencies (we will probably have to install some
more development packages for the native extensions):

    $ cd /path/to/kitbot
    $ bundle install

And run the bot:

    $ ruby kitbot.rb
