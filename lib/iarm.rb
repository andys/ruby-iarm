
['timer', 'msg', 'server', 'client', 'handle', 'channel'].each do |x|
  require("#{File.dirname(__FILE__)}/iarm/" + x)
end

