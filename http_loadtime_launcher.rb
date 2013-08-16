#!/usr/bin/env ruby
require 'rubygems'
require 'daemons'

# This runs the daemon (if it isn't already running)
Daemons.run('/usr/share/munin/plugins/http_loadtime_daemon.rb', { :dir_mode => :normal, :dir => "/tmp" })