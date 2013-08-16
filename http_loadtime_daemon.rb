#!/usr/bin/env ruby
require 'fileutils'

# This is the daemon that periodically checks http loadtimes and records them

DATA_DIR="/var/munin/run/http_loadtime"
DEFAULT_SLEEP=35 # time between checking on threads.
DEFAULT_TIMEOUT=30
DEFAULT_ERROR_VALUE=60
DEFAULT_REGEX_ERROR_VALUE=40
DEFAULT_GREP_OPTS="-E -i"
DEFAULT_WGET_OPTS="--no-cache --tries=1  -H -p --exclude-domains ad.doubleclick.net" # Do not load ads from doubleclick.
DEFAULT_JOIN_LINES=true
DEFAULT_PORTO="http"
DEFAULT_PORT=80
DEFAULT_PATH="/"
DEFAULT_MAX=120
DEFAULT_CRITICAL=30
DEFAULT_WARNING=25


#
# Next Steps:
#   - Record the last X runtimes, report an average to munin?
#   - Allow for the regex strings to check for an error condition in the html output
#

# Get the urls from config.
def get_urls()
  if (! ENV['names'])
    # We have no hosts to check, let's bail
  exit 1
  end
  urls = []
  i = 1
  ENV['names'].split(" ").each do |cururl|
    thisurl = {}
    # Label and url are required.
    thisurl[:label] = ENV["label_#{cururl}"]
    thisurl[:url] = ENV["url_#{cururl}"]
    thisurl[:name] = cururl
    # optional parameters
    thisurl[:warning] = (ENV["warning_#{cururl}"].nil?)?  nil : ENV["warning_#{cururl}"]
    thisurl[:critical] = (ENV["critical_#{cururl}"].nil?)? nil : ENV["critical_#{cururl}"]
    thisurl[:max] = (ENV["max_#{cururl}"].nil?)? nil : ENV["max_#{cururl}"]
    thisurl[:port] = (ENV["port_#{cururl}"].nil?)? nil : ENV["port_#{cururl}"]
    thisurl[:path] = (ENV["path_#{cururl}"].nil?)? nil : ENV["path_#{cururl}"]
    thisurl[:wget_post_data] = (ENV["wget_post_data_#{cururl}"].nil?)? nil : ENV["wget_post_data_#{cururl}"]
    thisurl[:error_value] = (ENV["error_value_#{cururl}"].nil?)? nil : ENV["error_value_#{cururl}"]
    thisurl[:regex_error_value] = (ENV["regex_error_value_#{cururl}"].nil?)? nil : ENV["regex_error_value_#{cururl}"]
    thisurl[:regex_header_1] = (ENV["regex_header_1_#{cururl}"].nil?)? nil : ENV["regex_header_1_#{cururl}"]
    thisurl[:grep_opts] = (ENV["grep_opts_#{cururl}"].nil?)? nil : ENV["grep_opts_#{cururl}"]
    thisurl[:wget_opts] = (ENV["wget_opts_#{cururl}"].nil?)? nil : ENV["wget_opts_#{cururl}"]
    thisurl[:join_lines] = (ENV["join_lines_#{cururl}"].nil?)? nil : ENV["join_lines_#{cururl}"]
    thisurl[:index] = i
    thisurl[:wget_output_file] = DATA_DIR + "/tmp/wget_output_"+cururl
    urls[i-1] = thisurl
    i+=1
  end
  return urls
end

# return the default settings for timeout, etc from config.
def get_defaults()
  defaults = {}
  defaults[:timeout] = (ENV["timeout"].nil?)? DEFAULT_TIMEOUT : ENV["timeout"]
  defaults[:error_value] = (ENV["error_value"].nil?)? DEFAULT_ERROR_VALUE : ENV["error_value"]
  defaults[:regex_error_value] = (ENV["regex_error_value"].nil?)? DEFAULT_REGEX_ERROR_VALUE : ENV["regex_error_value"]
  defaults[:grep_opts] = (ENV["grep_opts"].nil?)? DEFAULT_GREP_OPTS : ENV["grep_opts"]
  defaults[:wget_opts] = (ENV["wget_opts"].nil?)? DEFAULT_WGET_OPTS : ENV["wget_opts"]
  defaults[:join_lines] = (ENV["join_lines"].nil?)? DEFAULT_JOIN_LINES : ENV["join_lines"]
  defaults[:warning] = (ENV["warning"].nil?)? DEFAULT_WARNING : ENV["warning"]
  defaults[:critical] = (ENV["critical"].nil?)? DEFAULT_CRITICAL : ENV["critical"]
  defaults[:max] = (ENV["max"].nil?)? DEFAULT_MAX : ENV["max"]
  defaults[:proto] = (ENV["proto"].nil?)? DEFAULT_PORTO : ENV["proto"]
  defaults[:port] = (ENV["port"].nil?)? DEFAULT_PORT : ENV["port"]
  defaults[:path] = (ENV["path"].nil?)? DEFAULT_PATH : ENV["path"]
  return defaults
end

# compares instance settings to defaults, returns a complete instance-overridden config
def get_instance_config(cururl,defaults)
  instance_cfg = {}
  defaults.each { |key, value|
    if !cururl[key].nil?
      instance_cfg[key] = cururl[key]
    else
      instance_cfg[key] = value
    end
  }
  return instance_cfg
end

threads = {}

# TODO: use which to get full path.
wget_binary="wget"

# ensure directories exist
FileUtils.mkdir_p DATA_DIR+"/tmp"

loop do
  # read config & get urls
  urls = get_urls()

  # load up our defaults
  defaults = get_defaults()

  # check load times
  urls.each do |cururl|
    # check to see if we have a thread running already
    if !threads[cururl].nil?
      # skip thread generation...
      next
    end
    # Generate a thread!
    threads[cururl] = Thread.new(cururl) { |myurl|

      # build the wget options
      cfg = get_instance_config(cururl,defaults)

      # build exec call.
      wget_cmd = "#{wget_binary} --no-check-certificate --save-headers --no-directories "
      wget_cmd += "--output-document #{cururl[:wget_output_file]} "
      wget_cmd += "--timeout #{cfg[:timeout]} "
      # post data?
      if !cururl[:wget_post_data].nil?
        wget_cmd += "--post-data \"#{cururl[:wget_post_data]}\""
      end
      # additional options
      if (!cfg[:wget_opts].nil?)
        wget_cmd += "#{cfg[:wget_opts]} "
      end
      wget_cmd += "--header=\"Host:#{myurl[:url]}\" "
      wget_cmd += "#{cfg[:proto]}://localhost:#{cfg[:port]}#{cfg[:path]} "
      wget_cmd += "> /dev/null 2>&1"

      # start time
      beginning_time = Time.now
      # run our wget!
      system wget_cmd
      # end time
      end_time = Time.now
      elapsed_time = (end_time - beginning_time)  # time in seconds

      # TODO: make compat with bash script and use regex to check for error strings.

      # get results
      # save the time to our last run file
      filename = DATA_DIR + "/#{cururl[:label]}.last_run"
      begin
        File.open(filename, "w") {|f| f.write(elapsed_time) }
      rescue
        puts "Error saving to file: #{filename}"
      end
      this.exit
    }
  end

  puts "pre-cleanup: " + threads.length.to_s

  # clean up stopped threads
  threads.delete_if { |cururl, thread | !thread.alive? }

  # sleep a bit before we retry
  sleep(DEFAULT_SLEEP)
end

threads.each { |aThread|  aThread.join }
