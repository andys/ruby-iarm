
module Iarm
  class Handle
  
    attr_reader :touched_at, :created_at, :name, :timer
    attr_accessor :ttl, :msgs, :channels
  
    def initialize(name)
      @channels = {}
      @name = name
      @timer = Iarm::Timer.new
      @created_at = Time.now.to_i
      @ttl = 90
      @msgs = []
      self.touch
    end
  
    def timed_out?
      (@touched_at + @ttl) < Time.now.to_i
    end
  
    def no_msgs?
      @msgs.empty?
    end
  
    def touch
      @touched_at = Time.now.to_i
    end
    
    def timeout # returns list of channels that this handle was a member of
      @channels.keys.select do |channel|
        channel.members.delete(self) 
        channel.post(self, Msg::Timeout.new(channel.name, self.name))
        @channels.delete(channel)
        true
      end
    end


    def depart(channel) # returns a list of channels that we departed
      @channels.keys.select do |ch|
        if channel.nil? || ch == channel
          ch.members.delete(self)
          @channels.delete(ch)
          ch.post(self, Msg::Part.new(ch.name, self.name))
          true
        end
      end
    end
    
    def join(channel)
      @channels[channel] = channel.members[self] = Time.now.to_i
      send_msg(channel.topic) if channel.topic
      channel.post(self, Msg::Join.new(channel.name, self.name, @channels[channel]))
    end
    
    def send_msg(msg)
      if(msg.kind_of?(Msg::Topic) || @name != msg.from)
        @msgs << msg
        self.poke
      end
    end
    
    def poke
      @timer.poke
    end
    
    def say(channel, msg)
      channel.members.each_key {|member| member.send_msg(msg) }
    end
    
  end
end
