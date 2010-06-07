require '../iarm'

Thread.abort_on_exception = true

puts "Name?"
nick = gets
nick.chomp!

reader = Thread.new do
	puts "reader: Connecting"
	iarm = Iarm::Client.connect('drbunix:/tmp/.s.iarm')
	msg = nil
	loop do
		#sleep 1 if(msg.nil?)
		puts "reader: waiting for message"
		msg = iarm.getmsg(nick, 30)
		if(msg)
			if(msg.kind_of?(Iarm::Msg::Join))
				puts "#{msg.channel}: *** #{msg.from} #{msg.kind_of?(Iarm::Msg::ChannelMember) ? 'is in' : 'has joined'} the channel"
			elsif(msg.kind_of?(Iarm::Msg::Part))
				puts "#{msg.channel}: *** #{msg.from} has #{msg.kind_of?(Iarm::Msg::Timeout) ? 'timed out of' : 'departed'} the channel"
			else
				puts "#{msg.channel}: <#{msg.from}> #{msg.data}"
			end
		end
	end
end

puts "writer: connecting"
ia = Iarm::Client.connect('drbunix:/tmp/.s.iarm')
ch = nil

loop do
	puts "Input?"
	input = gets
	if(input)
		input.chomp!
		puts "writer: posting"
		if(input =~ /\/join (.*)$/)
			ch = $1
			puts "*** #{nick} joining #{ch}"
			ia.join(nick, ch)
		elsif(input =~ /\/part (.*)$/)
			ia.depart(nick, $1)
			puts "*** #{nick} departing #{$1}"
			ch = nil if(ch == $1)
		elsif(input =~ /\/quit$/)
			ia.depart(nick)
			reader.kill
			exit
		elsif(ch)
			puts "<#{nick}:#{ch}> #{input}"
			ia.post(Iarm::Msg.new(ch, nick, input))
		end
	end
end

