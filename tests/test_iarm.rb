  
require '../iarm'
require 'test/unit'

Thread.abort_on_exception = true

def socket_path
  'drbunix:/tmp/.s.testiarm'
end

Iarm::Server.start(socket_path)

module TestIarmServer

  
  def setup
    @client1 = new_client
    @client2 = new_client
  end
  
  def teardown
    @client1.depart('client1')
    @client1 = nil
    @client2.depart('client2')
    @client2 = nil
  end
  
  protected
  def new_client
    Iarm::Client.connect(socket_path) or raise 'Cannot connect'
  end
  

end

class TestIarm < Test::Unit::TestCase
  include TestIarmServer
  
  def test_join_and_speak
    @client1.join('client1', 'test_channel')
    @client2.join('client2', 'test_channel')

    join_msg = @client1.getmsg('client1', 1)
    assert_instance_of Iarm::Msg::Join, join_msg
    assert_equal 'client2', join_msg.from
    assert_equal 'test_channel', join_msg.channel
  end
  
  def test_topic
    @client1.join('client1', 'test_channel')
    
    
    topic = @client1.get_topic('test_channel')
    assert_nil topic
    
    @client1.set_topic('client1', 'test_channel', 'Channel Topic')
    topic = @client1.get_topic('test_channel')
    assert_kind_of Iarm::Msg::Topic, topic
    assert_equal 'Channel Topic', topic.data
    assert_equal 'client1', topic.from
    assert_equal 'test_channel', topic.channel
    
    @client2.join('client2', 'test_channel')
    topic = @client2.getmsg('client2', 1)
    assert_kind_of Iarm::Msg::Topic, topic
    assert_equal 'Channel Topic', topic.data
    assert_equal 'client1', topic.from
    assert_equal 'test_channel', topic.channel
    
    @client2.set_topic('client2', 'test_channel', 'New Topic')
    topic = @client1.get_topic('test_channel')
    assert_kind_of Iarm::Msg::Topic, topic
    assert_equal 'New Topic', topic.data
    assert_equal 'client2', topic.from
    assert_equal 'test_channel', topic.channel
  end
  
  def test_queued_msg
    @client1.join('client1', 'test_channel')
    @client2.join('client2', 'test_channel')
    @client1.say('client1', 'test_channel', 'test message')
    
    new_connection = new_client
    msg = new_connection.getmsg('client2', 1)
    assert_instance_of Iarm::Msg, msg
    assert_equal 'client1', msg.from
    assert_equal 'test_channel', msg.channel
    assert_equal 'test message', msg.data
  end
  
  def test_who
    @client1.join('client1', 'test_channel')
    channel_members = @client2.who('test_channel')
    assert_equal ['client1'], channel_members.keys.sort
    
    @client2.join('client2', 'test_channel')
    channel_members = @client2.who('test_channel')
    assert_equal ['client1', 'client2'], channel_members.keys.sort
  end
  
  def test_depart
    @client1.join('client1', 'test_channel')
    @client2.join('client2', 'test_channel')
    @client1.depart('client1', 'test_channel')
    msg = @client2.getmsg('client2', 1)
    assert_instance_of Iarm::Msg::Part, msg
    
    channel_members = @client2.who('test_channel')
    assert_equal ['client2'], channel_members.keys.sort
  end
  
  def test_depart_all
    @client1.join('client1', 'test_channel')
    @client1.join('client1', 'test_channel2')
    @client1.depart('client1')

    assert_equal [], @client2.who('test_channel').keys
    assert_equal [], @client2.who('test_channel2').keys
    
    assert_equal [], @client2.list
  end
  
  def test_server_running
    assert_equal 'pong', @client1.ping
  end
  
  def test_timeout
    @client1.ttl(2)
    @client1.join('client1', 'test_channel')
    assert_equal ['client1'], @client2.who('test_channel').keys
    sleep(Iarm::Server::REAPER_GRANULARITY + 1)
    assert_equal [], @client2.who('test_channel').keys
  end
end
