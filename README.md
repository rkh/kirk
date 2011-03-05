# Kirk: a JRuby Rack server based on Jetty

Kirk is a wrapper around Jetty that hides all of the insanity and wraps your
Rack application in a loving embrace. Also, Kirk is probably the least HTTP
retarded ruby rack server out there.

### TL;DR

    gem install kirk
    rackup -s Kirk config.ru

### Features

Here is a brief highlight of some of the features available.

* 0 Downtime deploys: Deploy new versions of your rack application without
  losing a single request. This happens atomically so it will work even under
  heavy load. Also, if the redeploy fails for some reason (the application fails
  to boot), then the previous application remains live.

* Request body streaming: Have a large request body to handle? Why wait until
  receiving the entire thing before starting the work?

* HTTP goodness: `Transfer-Encoding: chunked`, `Content-Encoding: gzip` (and
  deflate) support on the request.

* Concurrency: As it turns out, it's nice to not block your entire application
  while waiting for an HTTP request to finish. It's also nice to be able to
  handle more than 50 concurrent requests without burning over 5GB of RAM. Sure,
  RAM is cheap, but using Kirk is cheaper ;)

* Run on the JVM: I, for one, am a fan of having a predictable GC, a JIT
  compiler, and other goodness.

* Async API that lets you handle asynchronous responses with ease

### Getting Started

To take advantage of the zero downtime redeploy features, you will need to
create a configuration file that describes to Kirk how to start and watch the
rack application. You can create the file anywhere. For example, let's say that
we are going to put the following configuration file at `/path/to/Kirkfile`.

    # Set the log level to ALL.
    log :level => :all

    rack "/path/to/my/rackup/config.ru" do
      # Set the host and / or port that this rack application will
      # be available on. This defaults to "0.0.0.0:9090"
      listen 80

      # Set the host names that this rack application wll be available
      # on. This defaults to "*"
      hosts "example.com", "*.example.org"

      # Set arbitrary ENV variables
      env :RAILS_ENV => "production"

      # Set the file that controls the redeploys. This is relative to
      # the applications root (the directory that the rackup file lives
      # in). Touch this file to redepoy the application.
      watch "REVISION"
    end

    rack "/path/to/another/rackup/config.ru" do
      # More settings here
    end

Once you have Kirk configured, start it up with the following command:

    kirk -c /path/to/Kirkfile

... and you're off.

### Redeploying

As showed above, one way to trigger a redeploy is to specify a magic file to
watch and then touch it. While this is simple, it doesn't give you any insight
into the process of the redeploy. If the redeploy fails, there is no feedback.

Another way to deploy is by running `kirk redeploy -R /path/to/app/config.ru`

    $ kirk redeploy -R /path/to/app/config.ru
    Waiting for response...
    Redeploying application...
    Redeploy complete.

... that was easy.

### Daemonizing Kirk

Use your OS features. For example, write an upstart script or use
`start-stop-daemon`.

### Logging to a file or syslog

Kirk just dumps logs to stdout, so just pipe Kirk to `logger`.

### Async API

If you want to send asynchronous responses, you can use async API:

    class MyRackApp
      def call(env)
        async = env['kirk.async'].start!

        LongTask.run do
          async.respond(200, { 'Content-Type' => 'text/html' }, nil)
          async.respond(nil, nil, "Hello\n")
          async.respond(nil, nil, "World\n")
          async.respond(nil, nil, nil) # Finish the request
        end

        nil
      end
    end

### Kirk::Client - For all your HTTP needs

Need to make one off HTTP requests?

    resp = Kirk::Client.get 'http://www.google.com'
    puts resp.body

That was cool, but I wouldn't recommending doing that in your Rails app.
Following is the more advanced API.

First, create an instance of Kirk::Client. This object is thread-safe (or at
least it should be) and will manage your connection pool. Any connection that
can be kept alive will be stored by Kirk::Client and reused on subsequent requests.

    MY_CLIENT = Kirk::Client.new

Next, you'll want to implement a class to handle the responses. Just implement
any method that you want to use.

    class MyHandler
      # Handle exceptions
      def on_exception(exception)
      end

      # The request to the server has finished, but the
      # server has not responded yet.
      def on_request_complete
      end

      # The server has finished sending the response header
      def on_response_head(response)
        puts "STATUS: #{response.status}"
        response.headers.each do |name, val|
          puts "  #{name}: #{val}"
        end
      end

      # The server is sending the response body. This method could
      # be called multiple times depending on the number of chunks
      # that are received.
      #
      # Also, if this method is implemented, the response body won't
      # be buffered in the response object.
      def on_response_body(response, chunk)
        # response.body == nil
        print chunk
      end

      def on_response_complete(response)
        puts "The response has been received"
      end
    end

Now, you can start making the requests.

    MY_CLIENT.group do |g|

      # All of these requests will happen in parallel.
      g.get  'http://www.google.com',  MyHandler.new
      g.post 'http://www.twitter.com', MyHandler.new, "Some request body"
      g.get  'http://www.amazon.com', nil, nil, 'X-Custom-Header' => 'Blah'

      # The group will block until all of the requests are completed.
    end

You can also turn blocking off:
    MY_CLIENT.group :block => false do |g|
      g.get  'http://www.google.com',  MyHandler.new
      g.post 'http://www.twitter.com', MyHandler.new, "Some request body"
      g.get  'http://www.amazon.com', nil, nil, 'X-Custom-Header' => 'Blah'

      # group will return immediatly
    end

Hopefully that is enough to get started.

### Caveats

This is still a pretty new project and a lot of settings that should be
abstracted are still hardcoded in the source.

* Kirk requires JRuby 1.6.0 RC 1 or greater. This is due to a JRuby bug that
  was fixed in the 1.6 branch but never backported to older versions of JRuby.
  Crazy stuff happens without the bug fix.

* The JDBC drivers will keep connections open unless they are explicitly
  cleaned up, something which Rack applications do not do. A future release of
  the jdbc ruby drivers will correctly clean up after the JDBC garbage, but for
  now, you will have to manually do it. If you are running a Rails app, add the
  following to the config.ru file:

      at_exit { ActiveRecord::Base.clear_all_connections! }

### Getting Help

Ping me (carllerche) on Freenode in #carlhuda

### Reporting Bugs

Just post them to the Github repository's issue tracker.
