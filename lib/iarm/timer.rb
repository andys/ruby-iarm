
require 'thread'

module Iarm
  class Timer
    class Timeout < Exception; end
    class Poke < Exception; end
    
    def initialize
      @poked = false
      @mutex = Mutex.new
      @resource = ConditionVariable.new
    end
    
    def poke(timeout=false)
      @mutex.synchronize do 
        @poked = true if timeout
        @resource.signal
      end
    end
    
    def wait(timeout)
      timer = create_timer(timeout)
      should_wait = true
      should_wait = yield(true) if block_given?
      if should_wait
        @mutex.synchronize do 
          @resource.wait(@mutex) 
        end
      end
      @poked
    rescue Timeout
    ensure
      Thread.kill(timer) if(timer && timer.alive?)
      yield(false)  if block_given?
    end
    
    private
    def create_timer(timeout)
      return nil if(timeout.nil?)
      waiter = Thread.current
      Thread.start do
        sleep(timeout)
        poke(true)
      end
    end
    
    class << self 
      def poke(thr)
        if(thr)# && thr.stop?)
          thr.raise(Poke.new)
          true
        else
          false
        end
      end
      
      def wait(timeout)
        timer = create_timer(timeout)
        yield(true) if block_given?
        Thread.stop
      rescue Timeout
        return false
      rescue Poke
        return true
      ensure
        Thread.kill(timer) if(timer && timer.alive?)
        yield(false) if block_given?
      end
      
      def crit
        (@mutex ||= Mutex.new).synchronize { yield }
      end

      private
      def create_timer(timeout)
        return nil if(timeout.nil?)

        waiter = Thread.current
        Thread.start do
          Thread.pass
          sleep(timeout)
      #      Thread.critical = true
          waiter.raise(Timeout.new)
        end
      end
    end
  end
end
