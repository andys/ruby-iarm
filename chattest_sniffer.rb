require 'iarm'
iarm = Iarm::Client.connect('drbunix:/tmp/.s.iarm')
loop do
	msg = iarm.getmsg(nil, 50)
	if(msg)
		if(msg.kind_of?(Iarm::Msg::Join))
			puts "#{msg.channel}: *** #{msg.from} has joined the channel"
		elsif(msg.kind_of?(Iarm::Msg::Part))
			puts "#{msg.channel}: *** #{msg.from} has #{msg.kind_of?(Iarm::Msg::Timeout) ? 'timed out of' : 'departed'} the channel"
		else
			puts "#{msg.channel}: <#{msg.from}> #{msg.data}"
		end
	end
end
