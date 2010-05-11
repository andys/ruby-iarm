
require '../iarm'
require 'test/unit'

Thread.abort_on_exception = true

def socket_path
  #'drbunix:/tmp/.s.testiarm'
  'druby://timeline:60733'
end

iarm_server = Iarm::Server.new
DRb.start_service(socket_path, iarm_server)
@server = DRb.thread

module TestIarmServer

  
  def setup
    @client1 = new_client
    @client2 = new_client
  end
  
  def teardown
    @client1 = nil
    @client2 = nil
  end
  
  protected
  def new_client
    Iarm::Client.connect(socket_path)
  end
  

end

class TestIarm < Test::Unit::TestCase
  include TestIarmServer
  
  def test_join
    @client1.join('client1', 'test_channel')
    @client2.join('client2', 'test_channel')
    puts "Waiting for join message.."
    join_msg = @client1.getmsg('client1', 2)
    assert_instance_of Iarm::Msg::Join, join_msg
  end
  
  def test_server_running
    assert_equal 'pong', @client1.ping
  end
end
