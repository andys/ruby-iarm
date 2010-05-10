

Iarm::Msg = Struct.new(:channel, :from, :data)

['join', 'part', 'channel_member', 'timeout'].each do |x|
  require("#{File.dirname(__FILE__)}/msg/" + x)
end

