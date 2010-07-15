
module Iarm
  class Channel
  
  
    attr_reader :created_at, :name
    attr_accessor :members, :topic, :key
  
    def initialize(name)
      @name = name
      @key = key
      @members = {}
      @created_at = Time.now.to_i
      @topic = nil
    end
    
    def post(handle, msg)
      handle.say(self, msg)
    end
    
    def empty?
      @members.empty?
    end
    
    def members_by_name
      @members.keys.inject({}) {|hash,handle| hash[handle.name] = @members[handle] ; hash }
    end
  end
end
