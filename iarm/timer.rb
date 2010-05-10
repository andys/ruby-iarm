
require 'thread'

module Iarm
  class Timer
    class Timeout < Exception; end
    class Poke < Exception; end
    
    def self.poke(thr)
      crit do
        if(thr && thr.stop?)
          thr.raise(Poke.new)
          true
        else
          false
        end
      end
    end
    
    def self.wait(timeout, critflag=true)
      if(block_given?)
        critflag ? crit { yield(true) } : yield(true)
      end
      timer = create_timer(timeout)
      Thread.stop
    rescue Timeout
      return false
    rescue Poke
      return true
    ensure
      Thread.kill(timer) if(timer && timer.alive?)
      if(block_given?)
        critflag ? crit { yield(false) } : yield(false)
      end
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
