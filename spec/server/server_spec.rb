require 'spec_helper'

describe 'Kirk::Server' do
  it "runs a simple rack application" do
    start lambda { |env| [ 200, { 'Content-Type' => "text/plain" }, [ "Hello Rack" ] ] }

    get '/'
    last_response.should be_successful
    last_response.should have_body("Hello Rack")
  end

  it "runs the server" do
    start hello_world_path('config.ru')

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')
  end

  it "runs the server on the specified port" do
    path = hello_world_path('config.ru')

    start do
      log :level => :warning

      rack "#{path}" do
        listen 9091
      end
    end

    host! 'localhost', 9091

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')
  end

  it "can start multiple applications" do
    path1 = hello_world_path('config.ru')
    path2 = goodbye_world_path('config.ru')

    start do
      log :level => :warning

      rack "#{path1}" do
        listen '127.0.0.1:9090'
      end

      rack "#{path2}" do
        listen ':9090'
      end
    end

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')

    host! IP_ADDRESS, 9090

    get '/'
    last_response.should have_body('Goodbye World')
  end

  it "can start multiple applications on the same port" do
    path1 = hello_world_path('config.ru')
    path2 = goodbye_world_path('config.ru')

    start do
      log :level => :warning

      rack "#{path1}" do
        listen '127.0.0.1:9090'
      end

      rack "#{path2}" do
        listen '127.0.0.1:9090'
      end
    end

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')
  end

  it "can start the same application on multiple ports" do
    path = hello_world_path('config.ru')

    start do
      log :level => :warning

      rack "#{path}" do
        listen 9091, '127.0.0.1:9092'
      end
    end

    lambda {
      get '/'
    }.should raise_error(Errno::ECONNREFUSED)

    host! IP_ADDRESS, 9091

    get '/'
    last_response.should have_body('Hello World')

    host! IP_ADDRESS, 9092

    lambda {
      get '/'
    }.should raise_error(Errno::ECONNREFUSED)

    host! '127.0.0.1', 9092

    get '/'
    last_response.should have_body('Hello World')
  end

  it "can partition applications by the host name" do
    path1 = hello_world_path('config.ru')
    path2 = goodbye_world_path('config.ru')

    start do
      log :level => :warning

      rack "#{path1}" do
        hosts 'foo.com', 'bar.com'
      end

      rack "#{path2}" do
        hosts 'baz.com'
      end
    end

    get '/', {}, 'HTTP_HOST' => 'foo.com'
    last_response.should have_body('Hello World')

    get '/', {}, 'HTTP_HOST' => 'bar.com'
    last_response.should have_body('Hello World')

    get '/', {}, 'HTTP_HOST' => 'baz.com'
    last_response.should have_body('Goodbye World')

    get '/', {}, 'HTTP_HOST' => 'localhost'
    last_response.should be_missing
  end


  it "reloads the server" do
    path = randomized_app_path('config.ru')

    start do
      log :level => :warning

      rack "#{path}" do
        watch "REVISION"
      end
    end

    get '/'
    num = last_response.body

    get '/'
    last_response.body.should == num

    touch randomized_app_path('REVISION')
    # Gives the server the time to see the
    # revision change and reload the app
    sleep 2

    get '/'
    last_response.body.should_not == num
  end

  it "can watch a specified file to trigger redeploys" do
    path = randomized_app_path('config.ru')

    start do
      log :level => :warning

      rack "#{path}" do
        watch "redeploy.txt"
      end
    end

    get '/'
    num = last_response.body

    touch randomized_app_path('redeploy.txt')
    sleep 2

    get '/'
    last_response.body.should_not == num
  end

  after :each do
    @client.disconnect if @client
  end

  it "can redeploy an application on command" do
    start randomized_app_path('config.ru')

    get '/'
    num = last_response.body

    redeploy(randomized_app_path('config.ru')).should == [
      "Waiting for response...",
      "Redeploying application...",
      "Redeploy complete." ]

    get '/'
    last_response.body.should_not == num
  end

  it "provides information when the application doesn't exist" do
    start randomized_app_path('config.ru')

    get '/'
    num = last_response.body

    redeploy('/some/app/is/missing').should == [
      'Waiting for response...',
      '[ERROR] No application racked up at `/some/app/is/missing`' ]

    get '/'
    last_response.should have_body(num)
  end

  it "doesn't take down the application when an error happens during redeploy" do
    start randomized_app_path('config.ru')

    get '/'
    num = last_response.body

    File.open(randomized_app_path('config.ru'), 'w') do |f|
      f.puts <<-RUBY
        RAND = rand(10_000)

        raise 'fail'

        run lambda { |e| [ 200, { 'Content-Type' => 'text/plain' }, [ RAND.to_s ] ] }
      RUBY
    end

    redeploy(randomized_app_path("config.ru")).should == [
      "Waiting for response...",
      "Redeploying application...",
      "[ERROR] Something went wrong" ]

    File.open(randomized_app_path('config.ru'), 'w') do |f|
      f.puts <<-RUBY
        RAND = "RAND"

        run lambda { |e| [ 200, { 'Content-Type' => 'text/plain' }, [ RAND.to_s ] ] }
      RUBY
    end

    redeploy(randomized_app_path("config.ru")).should == [
      "Waiting for response...",
      "Redeploying application...",
      "Redeploy complete." ]

    get '/'
    last_response.should have_body('RAND')
  end

  it "can load config files relative to the current file" do
    kirkup kirked_up_path("Kirkfile")

    get '/'
    last_response.should have_body('Hello World')

    host! 'localhost', 9091

    get '/'
    last_response.should have_body('Goodbye World')
  end

  it "can load config files w/ a glob relative to the current file" do
    kirkup kirked_up_path("Kirkfile")

    host! 'localhost', 9092

    get '/'
    last_response.should receive_request_method('GET')
  end

  it "can rackup applications that don't use config.ru as the rackup file" do
    start blacksheep_path('not_config.ru')

    get '/'
    last_response.should be_successful
    last_response.should have_body("Black Sheep")
  end

  it "provides a friendly error when the file being loaded doesn't exist" do
    lambda do
      start do
        load "zomgHI2U"
      end
    end.should raise_error(Kirk::MissingConfigFile)
  end

  it "keeps the default umask in child applications" do
    start umask_path('config.ru')

    get '/'
    last_response.should have_body("umask: 18")
  end

  it "can set the ENV for a specific application without it leaking over" do
    path = reveal_env_path('config.ru')

    start do
      rack "#{path}" do
        listen 9090
        env :FOO => 'Bar', "BAZ" => :OMG
      end

      rack "#{path}" do
        listen 9091
      end
    end

    get '/'

    ["FOO Bar", "BAZ OMG"].each do |line|
      last_response.body.should include(line)
    end

    host! "127.0.0.1", 9091

    get '/'
    last_response.body.should_not =~ /FOO/
  end

  it "handles cookie headers properly" do
    start lambda { |env| [ 200, { 'Cookie' => "a=b\nc=d" }, [ "Hello Cookie" ] ] }

    get '/'
    last_response.headers["Cookie"].should == "a=b, c=d"
  end

  it "exposes async API to handle" do
    start lambda { |env|
      async = env['kirk.async'].start!

      Thread.new do
        sleep(0.1) # be sure that response is delayed
        async.respond(200, {'Content-Type' => 'text/html'}, nil)
        async.respond(nil, nil, "Hello\n")
        async.respond(nil, nil, "World\n")
        async.respond(nil, nil, nil) # Finish the request
      end.run

      nil
    }

    get '/'
    last_response.body.should == "Hello\nWorld\n"
  end
end
