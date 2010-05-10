
require 'drb'
require 'iarm'

Thread.abort_on_exception = true

server = Iarm::Server.new
DRb.start_service(ARGV[0].nil? ? 'drbunix:/tmp/.s.iarm' : ARGV[0], server)
DRb.thread.join

