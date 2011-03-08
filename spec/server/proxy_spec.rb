require 'spec_helper'

describe 'Kirk::Server::Middleware::Proxy' do

  before do
    start_echo_app
    @endpoint = lambda do |env|
      [200, {'Content-Type' => 'text/plain'}, "Hello"]
    end
  end

  after do
    @echo_server.stop if @echo_server
  end

  it "proxies each request if no options are provided" do
    start_default_proxy

    header 'X-My-Header', 'foo/bar'
    get '/http://localhost:9091/foo?bar=baz', {}, :input => "ZOMG"
    last_response.should be_successful
    last_response.should receive_path('/foo')
    last_response.should receive_request_method('GET')
    last_response.should receive_body('ZOMG')
    last_response.should receive_header('X-My-Header', 'foo/bar')
    last_response.should receive_query_string('bar=baz')
  end

  it "removes not needed headers" do
    start_default_proxy

    forbidden_headers = Kirk::Server::Middleware::Proxy::DO_NOT_PROXY_HEADERS
    forbidden_headers.each do |h|
      header h, 'foo'
    end

    get '/http://localhost:9091/'

    last_response.should be_successful

    forbidden_headers.each do |h|
      last_response.should_not receive_header(h)
    end
  end

  it "removes 'Connection: keep-alive' and 'Connection: close' headers" do
    start_default_proxy
    header 'Connection', 'keep-alive'
    header 'Keep-Alive', '100'
    get '/http://localhost:9091/'
    last_response.should be_successful
    last_response.should_not receive_header('Connection')
    last_response.should_not receive_header('Keep-Alive')

    header 'Connection', 'close'
    get '/http://localhost:9091/'
    last_response.should be_successful
    last_response.should_not receive_header('Connection')

    header 'Connection', 'foo'
    header 'Foo',        '200'
    get '/http://localhost:9091/'
    last_response.should be_successful
    last_response.should_not receive_header('Connection')
    last_response.should_not receive_header('Foo')
  end

  def start_default_proxy
    proxy = Kirk::Server::Middleware::Proxy.new(@endpoint)
    start proxy
  end

  def start_echo_app
    app_path = echo_app_path('config.ru')
    blk ||= lambda do
      log :level => :warning

      rack app_path do
        listen ':9091'
        env :BUNDLE_BIN_PATH => nil, :BUNDLE_GEMFILE => nil
      end
    end

    @echo_server = Kirk::Server.build(&blk)
    @echo_server.start
  end
end


