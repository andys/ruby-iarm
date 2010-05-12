
require 'drb'

module Iarm
  class Client
    def self.connect(server)
      #DRb.start_service
      DRbObject.new(nil, server)
    end
  end
end
