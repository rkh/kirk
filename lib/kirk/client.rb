require 'kirk'

module Kirk
  class Client
    require 'kirk/client/group'
    require 'kirk/client/response'
    require 'kirk/client/request'
    require 'kirk/client/exchange'

    def self.client
      @client ||= new
    end

    def self.stop
      @client.stop if @client
      @client = nil
    end

    def self.group(opts = {}, &blk)
      client.group(opts, &blk)
    end

    def group(opts = {}, &blk)
      Group.new(self, opts).tap do |group|
        group.start(&blk)
      end
    end

    def initialize(opts = {})
      @options = opts
    end

    def client
      @client ||= Jetty::HttpClient.new.tap do |client|
        client.set_connector_type(Jetty::HttpClient::CONNECTOR_SELECT_CHANNEL)
        client.set_thread_pool(thread_pool) if thread_pool
        client.start
      end
    end

    def process(request)
      exchange = Exchange.from_request(request)
      client.send(exchange)
    end

    def stop
      client.stop
    end

  private

    def thread_pool
      @options[:thread_pool]
    end
  end
end
