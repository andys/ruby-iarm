
require 'thread'

module Iarm
  class Timer
    class Timeout < Exception; end
    class Poke < Exception; end
    
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
        (@mutex ||= Mutex.new).syncronize { yield }
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
