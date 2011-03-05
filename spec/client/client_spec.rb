require 'spec_helper'
require 'kirk/client'

java_import org.eclipse.jetty.util.thread.QueuedThreadPool

describe 'Kirk::Client' do

  describe "requests" do
    before do
      start echo_app_path('config.ru')
    end

    it "allows to pass block for request" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_complete(response)
          @buffer << response
        end
      end

      @buffer = []
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        body = "foobar"

        g.request do |r|
          r.method  :post
          r.url     "/foo"
          r.handler handler.new(@buffer)
          r.headers "Accept" => "text/plain", :Bizz => :bazz
          r.body    body
        end
      end

      response = parse_response(group.responses.first)
      response["PATH_INFO"].should == "/foo"
      response["HTTP_ACCEPT"].should == "text/plain"
      response["REQUEST_METHOD"].should == "POST"
      response["HTTP_BIZZ"].should == "bazz"
      response["rack.input"].should == "foobar"
      @buffer.should == group.responses
    end

    it "allows to use simplified syntax" do
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        g.get    '/'
        g.put    '/'
        g.post   '/'
        g.delete '/'
      end

      responses = parse_responses(group.responses)
      responses.map {|r| r["REQUEST_METHOD"] }.sort.should == ["DELETE", "GET", "POST", "PUT"]
    end

    it "performs simple GET" do
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/"
      end

      group.should have(1).responses
      response = parse_response(group.responses.first)
      response["PATH_INFO"].should == "/"
      response["REQUEST_METHOD"].should == "GET"
    end

    it "performs more than one GET" do
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/foo"
        s.request :GET, "http://localhost:9090/bar"
      end

      group.should have(2).responses
      parse_responses(group.responses).map { |r| r["PATH_INFO"] }.sort.should == %w(/bar /foo)
    end

    it "performs POST request" do
      body = "zomg"
      group = Kirk::Client.group do |g|
        g.request :POST, "http://localhost:9090/", nil, body, {'Accept' => 'text/html'}
      end

      response = parse_response(group.responses.first)
      response["HTTP_ACCEPT"].should    == "text/html"
      response["REQUEST_METHOD"].should == "POST"
      response["rack.input"].should     == "zomg"
    end

    it "allows to pass body as IO" do
      body = StringIO.new "zomg"
      group = Kirk::Client.group do |g|
        g.request :POST, "http://localhost:9090/", nil, body
      end

      response = parse_response(group.responses.first)
      response["rack.input"].should == "zomg"
    end
  end

  it "sets the response status when it is successful" do
    start lambda { |env| [ 200, { 'Content-Type' => 'text/plain' }, ['Hello'] ] }

    resp = Kirk::Client.get 'http://localhost:9090/'
    resp.status.should == 200
  end

  it "sets the response status when it is 201" do
   start lambda { |env| [ 201, { 'Content-Type' => 'text/plain' }, ['Hello'] ] }

   resp = Kirk::Client.get 'http://localhost:9090/'
   resp.status.should == 201
  end

  it "sets the response status when it is 302" do
    start lambda { |env| [ 302, { 'Content-Type' => 'text/plain' }, ['Hello'] ] }

    resp = Kirk::Client.get 'http://localhost:9090/'
    resp.status.should == 302
  end

  it "fetches all the headers" do
    headers = { 'Content-Type' => 'text/plain', 'X-FooBar' => "zomg" }
    start(lambda { |env| [ 200, headers, [ "Hello" ] ] })

    headers.to_a.sort { |a, b| a.first <=> b.first }.should ==
      [['Content-Type', 'text/plain'], ['X-FooBar', 'zomg']]
  end

  it "allows to stream body" do
    handler = Class.new do
      def initialize(buffer)
        @buffer = buffer
      end

      def on_response_body(resp, content)
        @buffer << content
      end
    end

    class Body
      def initialize(output)
        @output = output
      end

      def body
        ['a', 'b']
      end

      def each
        body.each do |e|
          yield e
          @output.flush
        end
      end
    end

    start(lambda { |env| [200, {}, Body.new(env['kirk.output'])] })

    @buffer = []

    group = Kirk::Client.group do |s|
      s.request :GET, "http://localhost:9090/", handler.new(@buffer)
    end

    sleep(0.05)
    group.should have(1).responses
    @buffer.should == ["a", "b"]
  end

  context "callbacks" do
    it "handles on_response_complete callback" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_complete(response)
          @buffer << response
        end
      end

      start_default_app

      @buffer = []
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/", handler.new(@buffer)
      end

      sleep(0.05)
      @buffer.first.should == group.responses.first
    end

    it "handles on_response_head callback" do
      handler = Class.new do
        def initialize(buffer)
          @buffer = buffer
        end

        def on_response_head(resp)
          @buffer << resp.headers
        end
      end

      start_default_app

      @buffer = []
      group = Kirk::Client.group do |s|
        s.request :GET, "http://localhost:9090/", handler.new(@buffer)
      end

      sleep(0.05)
      @buffer.first.should == {
        'Content-Type'   => 'text/plain',
        'Content-Length' => '5',
        'Server'         => 'Jetty(7.3.0.v20110203)'
      }
    end

    it "calls complete callback after finishing all the requests" do
      start_default_app

      @completed = false
      group = Kirk::Client.group(:host => "localhost:9090") do |g|
        g.get "/"
        g.complete do
          @completed = true
        end
      end

      group.should have(1).responses
      @completed.should be_true
    end

    it "handles exceptions in the callbacks" do
      start_default_app

      handler = Class.new do
        def on_request_complete(*)
          raise "fail"
        end
      end

      resp = Kirk::Client.get 'http://localhost:9090/', handler.new
      resp.success?.should be_false
      resp.exception?.should be_true
    end
  end

  it "allows to set thread_pool" do
    start_default_app

    my_thread_pool = Class.new(QueuedThreadPool) do
      def initialize(buffer)
        @buffer = buffer
        super()
      end

      def dispatch(job)
        @buffer << 1
        super(job)
      end
    end

    @buffer = []
    thread_pool = my_thread_pool.new(@buffer)
    client = Kirk::Client.new(:thread_pool => thread_pool)

    client.group(:host => "http://localhost:9090") do |g|
      g.get "/"
      g.get "/foo"
    end

    @buffer.length.should > 0
    client.client.get_thread_pool.should == thread_pool

    client.stop
  end

  it "allows to run group on instance" do
    start_default_app

    client = Kirk::Client.new
    result = client.group do |g|
      g.request :GET, "http://localhost:9090/"
    end

    result.responses.first.body.should == "Hello"
  end

  it "allows to set host for group" do
    start_default_app

    group = Kirk::Client.group(:host => "localhost:9090") do |g|
      g.request :GET, "/"
    end

    group.responses.first.body.should == "Hello"
  end

  it "allows to avoid blocking" do
    start(lambda { |env| sleep(0.1); [ 200, {}, 'Hello' ] })

    group = Kirk::Client.group(:host => "localhost:9090", :block => false) do |g|
      g.get "/"
    end

    group.should have(0).responses

    group.join
    group.should have(1).responses
  end

  it "passes self to group" do
    client = Kirk::Client.new
    group = client.group {}
    group.client.should == client
  end

  def start_default_app
    start(lambda { |env| [ 200, { 'Content-Type' => 'text/plain' }, [ "Hello" ] ] })
  end

  def parse_response(response)
    Marshal.load(response.body)
  end

  def parse_responses(responses)
    responses.map { |r| parse_response(r) }
  end
end
