
require 'thread'
require 'drb'


module Iarm
  class Server

    def ping(nickname=nil)
      touch_nickname(nickname) if nickname
      'pong'
    end

    def ttl(nickname, ttl_secs)
      handle = touch_nickname(nickname)
      handle.ttl = ttl_secs
    end

    def list(pattern=nil)
      pattern ? @channels.keys.grep(pattern) : @channels.keys
    end
    
    def who(channelname)
      (ch = find_channel(channelname)) && ch.members_by_name || {}
    end

    def join(who, channelname, key=nil)      # returns true if joined, false if denied, and nil if new channel formed
      retval = nil
      handle = touch_nickname(who)
      @mutex.synchronize do
        if(channel = find_channel(channelname))
          retval = channel.key == key		# verify password
        else
          @channels[channelname].key = key 	# create the channel
        end

        if(retval != false)  # if retval is true (joined existing) or nil (new channel formed)
          if(!(channel = @channels[channelname]).members.has_key?(handle)) # don't re-join them if they've already joined before
            handle.join(channel)
          end
        end
      end
      retval
    end 

    def depart(nickname, channelname=nil)  # nil=depart ALL channels and log out client
      @mutex.synchronize do
        handle = touch_nickname(nickname)
        if channelname
          if(channel = find_channel(channelname))
            handle.depart(channel)
            check_channel_empty(channel)
          end
        else
          handle.depart(nil).each {|ch| check_channel_empty(ch) }
          @handles.delete(nickname)
        end
      end
    end

    # getmsg(): NOTES
      # returns msg or nil if no messages and timed out.
      # also serves as a keep-alive to avoid getting killed by ttl 
      # if who=nil then it listens on all channels, but only one client can do this at once
      # if another client is already listening with the same who-id, it has the effect of making them return immediately (before their timeout is up)
    def getmsg(who, timeout=0)
      handle = touch_nickname(who)
      if(timeout != 0 && handle.no_msgs?)
        handle.poke

        handle.timer.wait(timeout) do |mode|
          mode && handle.no_msgs?
        end
      end
      @mutex.synchronize { handle.msgs.shift }
    end
    
    def getmsgs(who, timeout=0)
      res = [ getmsg(who, timeout) ]
      while(!res.empty? && (msg = getmsg(who, 0)))
        res << msg
      end
      res
    end

    def say(nickname, channelname, data)
      handle = touch_nickname(nickname)
      if(channel = find_channel(channelname))
        channel.post(handle, Iarm::Msg.new(channelname, nickname, data))
      end
    end
    
    def set_topic(nickname, channelname, topic_data)
      handle = touch_nickname(nickname)
      if(channel = find_channel(channelname))
        topic_data = Msg::Topic.new(channelname, nickname, topic_data) unless topic_data.kind_of?(Msg::Topic)
        if(channel.topic != topic_data)
          channel.topic = topic_data
          channel.post(handle, topic_data)
          topic_data
        end
      end
    end
    
    def get_topic(channelname)
      if(channel = find_channel(channelname))
        channel.topic
      end
    end

    def self.start(uri=nil)
      DRb.start_service(uri, self.new)
      DRb.thread
    end
    
    private
    REAPER_GRANULARITY = 5  #seconds
    
    def initialize
      @mutex = Mutex.new()
      @reaper_mutex = Mutex.new()
      @handles = Hash.new()            # { nickname => Handle object }
      @channels = Hash.new() {|hsh,key| hsh[key] = Iarm::Channel.new(key) }
      @timeout_queue = []
      reaper_thread
    end
    
    def touch_nickname(nickname, refresh=true) # returns Handle object
      @reaper_mutex.synchronize do
        handle = @handles[nickname] ||= Iarm::Handle.new(nickname)
        handle.touch
        if(refresh)
          timeout_box = (handle.ttl.to_f / REAPER_GRANULARITY).ceil.to_i #/
          @timeout_queue[timeout_box] ||= {}
          @timeout_queue[timeout_box][handle] = true
        end
      end
      @handles[nickname]
    end
    
    def find_channel(channelname)
      @channels[channelname] if @channels.has_key?(channelname)
    end
    
    def reaper_thread
      @reaper ||= Thread.new do
        loop do
          kill_list = []
          sleep REAPER_GRANULARITY
          @reaper_mutex.synchronize do
            if(timeoutlist = @timeout_queue.shift)
              kill_list = timeoutlist.keys.select {|who| who.timed_out? }
            end
          end
          @mutex.synchronize do
            kill_list.each do |who|
              who.timeout.each {|ch| check_channel_empty(ch) }
              @handles.delete(who.name)
            end
          end
        end
      end
    end

    def clockval
      Time.new.to_i
    end

    def check_channel_empty(channel)
      if(channel.empty?)
        @channels.delete(channel.name)
      end
    end

  end
end
