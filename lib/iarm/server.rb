
require 'thread'
require 'drb'



module Iarm
  class Server

    def ping
      'pong'
    end
    def ttl(ttl_secs)
      @ttl_secs = ttl_secs
    end

    def list(pattern=nil)
      pattern ? @channels.keys.grep(pattern) : @channels.keys
    end
    
    def who(channel)
      if(@channels.has_key?(channel))
        @channel_members[channel] #.each {|w,time| post_msg(who, Msg::ChannelMember.new(channel, w, time)) } 
      else
        {}
      end
    end

    def join(who, channel, key=nil)      # returns true if joined, false if denied, and nil if new channel formed
      retval = nil
      touch_nickname(who)
      @mutex.synchronize do
        if(@channels.has_key?(channel))
          retval = (@channels[channel] == key) 
        else
          @channels[channel] = key
        end

        if(retval != false)  # if retval is true (joined existing) or nil (new channel formed)
          if(!@channel_members[channel].has_key?(who)) # don't re-join them if they've already joined before
            @channel_members[channel][who] = clockval
            @channels_joined[who] << channel
            send_msg(Msg::Join.new(channel, who, @channel_members[channel][who]))
            post_msg(who, @topics[channel]) if @topics.has_key?(channel)
          end
        end
      end
      retval
    end 

    def depart(who, channel=nil)  # nil=depart ALL channels and log out client
      @mutex.synchronize do
        (channel.nil? ? @channels_joined[who] : [ channel ]).each do |ch|
          @channels_joined[who].delete(ch)
          if @channel_members[ch].delete(who)
            send_msg(Msg::Part.new(ch, who))
          end
          check_channel_empty(ch)
        end
        kill_client(who) if(channel.nil?)
      end
      
    end

    # getmsg(): NOTES
      # returns msg or nil if no messages and timed out.
      # also serves as a keep-alive to avoid getting killed by ttl 
      # if who=nil then it listens on all channels, but only one client can do this at once
      # if another client is already listening with the same who-id, it has the effect of making them return immediately (before their timeout is up)
    def getmsg(who, timeout=0)
      if(@msgs[who].empty? && timeout != 0)
        wait_existing = false
        msg = @mutex.synchronize do
          wait_existing = Iarm::Timer.poke(@listeners[who])
          next_msg(who)
        end
        return msg if(msg)
        
        if(wait_existing)
          Thread.pass while(@mutex.synchronize { @listeners.has_key?(who) })
        end

        #puts "Timer.wait: timeout=#{timeout}"
        Iarm::Timer.wait(timeout) do |mode|
          @mutex.synchronize do
            mode ? @listeners[who] = Thread.current : @listeners.delete(who)
          end
          #puts "IARM getmsg: #{who} #{mode ? 'entering' : 'exiting'} wait with msgcount=#{@msgs[who].length}"
          Iarm::Timer.poke(Thread.current) if mode && @msgs[who].length>0  # don't bother sleeping if we already have a new message waiting
        end
      end
      @mutex.synchronize { next_msg(who) }
    end
    
    def getmsgs(who, timeout=0)
      res = [ getmsg(who, timeout) ]
      while(!res.empty? && (msg = getmsg(who, 0)))
        res << msg
      end
      res
    end

    def say(who, channel, data)
      post(Iarm::Msg.new(channel, who, data))
    end
    
    def set_topic(who, channel, data)
      touch_nickname(who)
      if @channels.has_key?(channel)
        data = Msg::Topic.new(channel, who, data) unless data.kind_of?(Msg::Topic)
        if(@topics[channel] != data)
          @mutex.synchronize { @topics[channel] = data }
          post(data)
          data
        end
      end
    end
    
    def get_topic(channel)
      @topics[channel]
    end

    def post(msg)
      @mutex.synchronize { send_msg(msg) } if(msg.kind_of?(Msg))
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
      @ttl_secs = 60
      @listeners = Hash.new()            # { who => Thread }
      @msgs = Hash.new() {|hsh,key| hsh[key] = [ ] }  # { who => [ msg1, msg2, ...] }
      @clients = Hash.new()            # { who => time_of_last_activity }
      @channel_members = Hash.new() {|hsh,key| hsh[key] = { } }  # { channelname => { who1 => join_time }, who2 =>  ...] }
      @channels_joined = Hash.new() {|hsh,key| hsh[key] = [ ] }  # { who => [ channel1, channel2 ] }
      @channels = Hash.new()             # { channelname => password }
      @topics = Hash.new()		# { channelname => topic }
      @timeout_queue = []
      reaper_thread
    end
    
    def touch_nickname(nickname) #TODO: call this
      # UPTO THERE
      timeout_box = @ttl_secs / REAPER_GRANULARITY #/
      @reaper_mutex.synchronize do
        @timeout_queue[timeout_box] ||= []
        @timeout_queue[timeout_box] << nickname
        @clients[nickname] = clockval
      end
    end
    
    
=begin
  reaper ideas
  ------------
  
  have a linked list which is in order of things to timeout
  when taking something off the list, check its actual timeout value and put it back to sleep if needed
  this could be a binary search down the track, for performance
  
=end    
    
    def timed_out?(nickname)
      (tla = @clients[nickname]) && (tla + @ttl_secs) < clockval
    end
    
    def reaper_thread
      @reaper ||= Thread.new do
        loop do
          kill_list = []
          sleep REAPER_GRANULARITY
          @reaper_mutex.synchronize do
            timeoutlist = @timeout_queue.shift
            if timeoutlist
              timeoutlist.each do |who|
                kill_list << who if timed_out?(who)
              end
            end
          end
          @mutex.synchronize do
            kill_list.each do |who|
              if(@channels_joined.has_key?(who))
                @channels_joined[who].each do |ch|
                  @channel_members[ch].delete(who)
                  send_msg(Msg::Timeout.new(ch, who))
                  check_channel_empty(ch)
                end
              end
              kill_client(who)
            end
          end
        end
      end
    end

    def clockval
      Time.new.to_i
    end
    
    def send_msg(msg)
      @channel_members[msg.channel].each_key {|w| post_msg(w, msg) }
      post_msg(nil, msg) if(@clients.has_key?(nil))
    end
    def post_msg(who, msg)
      if(msg.kind_of?(Msg::Topic) || who != msg.from)
        @msgs[who] << msg
        Iarm::Timer.poke(@listeners[who]) if(@listeners.has_key?(who))
      end
    end
    def next_msg(who) # returns msg or nil
      touch_nickname(who)
      @msgs[who].shift
    end
    def check_channel_empty(channel)
      if(@channel_members[channel].empty?)
        @channels.delete(channel)
        @channel_members.delete(channel)
        @topics.delete(channel)
      end
    end
    def kill_client(who)
      @channels_joined[who].each do |ch|
        @channel_members[ch].delete(who)
        check_channel_empty(ch)
      end
      @channels_joined.delete(who)
      @clients.delete(who)
      @msgs.delete(who)
      @listeners.delete(who)
    end

  end
end
