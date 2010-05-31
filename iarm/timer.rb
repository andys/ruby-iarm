
require 'thread'

module Iarm
  class Timer
    class Timeout < Exception; end
    class Poke < Exception; end
    
    def self.poke(thr)
      crit do
        if(thr)# && thr.stop?)
          thr.raise(Poke.new)
          true
        else
          false
        end
      end
    end
    
    def self.wait(timeout)
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
    
    def self.crit
      yield
    end

    private
    def self.create_timer(timeout)
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
