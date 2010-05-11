
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
        @channel_members[channel].keys
      end
    end

    def join(who, channel, key=nil)      # returns true if joined, false if denied, and nil if new channel formed
      retval = nil
      @mutex.synchronize do
        if(@channels.has_key?(channel))
          retval = (@channels[channel] == key) 
        else
          @channels[channel] = key
        end

        if(retval != false)  # if retval is true (joined existing) or nil (new channel formed)
          @channel_members[channel].each {|w,time| post_msg(who, Msg::ChannelMember.new(channel, w, time)) } if(retval)
          if(!@channel_members[channel].has_key?(who)) # don't re-join them if they've already joined before
            @channel_members[channel][who] = Time.now.to_i
            @channels_joined[who] << channel
            send_msg(Msg::Join.new(channel, who, @channel_members[channel][who]))
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
      puts "Getting message for #{who}: #{@msgs[who].inspect}"
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

        Iarm::Timer.wait(timeout, false) {|mode| @mutex.synchronize { mode ? @listeners[who] = Thread.current : @listeners.delete(who) } }
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

    def post(msg)
      @mutex.synchronize { send_msg(msg) } if(msg.kind_of?(Msg))
    end

    private
    def initialize
      @mutex = Mutex.new()
      @ttl_secs = 60
      @listeners = Hash.new()            # { who => Thread }
      @msgs = Hash.new() {|hsh,key| hsh[key] = [ ] }  # { who => [ msg1, msg2, ...] }
      @clients = Hash.new()            # { who => time_of_last_activity }
      @channel_members = Hash.new() {|hsh,key| hsh[key] = { } }  # { channelname => { who1 => join_time }, who2 =>  ...] }
      @channels_joined = Hash.new() {|hsh,key| hsh[key] = [ ] }  # { who => [ channel1, channel2 ] }
      @channels = Hash.new()             # { channelname => password }
      reaper_thread
    end
    
    def reaper_thread
      @reaper ||= Thread.new do
        loop do
          sleep 5
          @mutex.synchronize do
            @clients.each do |who, tla|
              next if((tla + @ttl_secs) > Time.new.to_i)
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

    def send_msg(msg)
      @channel_members[msg.channel].each_key {|w| post_msg(w, msg) }
      post_msg(nil, msg) if(@clients.has_key?(nil))
    end
    def post_msg(who, msg)
      if(who != msg.from)
        @msgs[who] << msg
        Iarm::Timer.poke(@listeners[who]) if(@listeners.has_key?(who))
      end
    end
    def next_msg(who) # returns msg or nil
      @clients[who] = Time.new.to_i     # touch
      @msgs[who].shift
    end
    def check_channel_empty(channel)
      if(@channel_members[channel].empty?)
        @channels.delete(channel)
        @channel_members.delete(channel)
      end
    end
    def kill_client(who)
      @channels_joined.delete(who)
      @clients.delete(who)
      @msgs.delete(who)
      @listeners.delete(who)
    end

  end
end
