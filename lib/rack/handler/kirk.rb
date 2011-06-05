require 'kirk'

module Rack
  module Handler
    class Kirk
      def self.run(app, options = {})
        options[:host] = options[:Host]
        options[:port] = options[:Port]

        options[:log_level] ||= "warning"

        server = ::Kirk::Server.new(app, options)

        yield server if block_given?

        # Tears :'(
        trap(:INT) { server.stop }

        server.start
        server.join
      end
    end
  end
end
