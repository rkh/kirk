module Kirk
  class Server
    class Handler < Jetty::AbstractHandler
      java_import 'java.util.zip.GZIPInputStream'
      java_import 'java.util.zip.InflaterInputStream'

      # Trigger the autoload so that the first access to the class
      # does not happen in a thread.
      InputStream

      # Required environment variable keys
      REQUEST_METHOD = 'REQUEST_METHOD'.freeze
      SCRIPT_NAME    = 'SCRIPT_NAME'.freeze
      PATH_INFO      = 'PATH_INFO'.freeze
      QUERY_STRING   = 'QUERY_STRING'.freeze
      SERVER_NAME    = 'SERVER_NAME'.freeze
      SERVER_PORT    = 'SERVER_PORT'.freeze
      LOCAL_PORT     = 'LOCAL_PORT'.freeze
      CONTENT_TYPE   = 'CONTENT_TYPE'.freeze
      CONTENT_LENGTH = 'CONTENT_LENGTH'.freeze
      REQUEST_URI    = 'REQUEST_URI'.freeze
      REMOTE_HOST    = 'REMOTE_HOST'.freeze
      REMOTE_ADDR    = 'REMOTE_ADDR'.freeze
      REMOTE_USER    = 'REMOTE_USER'.freeze

      # Rack specific variable keys
      RACK_VERSION      = 'rack.version'.freeze
      RACK_URL_SCHEME   = 'rack.url_scheme'.freeze
      RACK_INPUT        = 'rack.input'.freeze
      RACK_ERRORS       = 'rack.errors'.freeze
      RACK_MULTITHREAD  = 'rack.multithread'.freeze
      RACK_MULTIPROCESS = 'rack.multiprocess'.freeze
      RACK_RUN_ONCE     = 'rack.run_once'.freeze
      HTTP_PREFIX       = 'HTTP_'.freeze

      # Rack response header names
      CONTENT_TYPE_RESP   = 'Content-Type'
      CONTENT_LENGTH_RESP = 'Content-Length'

      # Kirk information
      SERVER          = "#{NAME} #{VERSION}".freeze
      SERVER_SOFTWARE = 'SERVER_SOFTWARE'.freeze

      DEFAULT_RACK_ENV = {
        SERVER_SOFTWARE => SERVER,

        # Rack stuff
        RACK_ERRORS       => STDERR,
        RACK_MULTITHREAD  => true,
        RACK_MULTIPROCESS => false,
        RACK_RUN_ONCE     => false,
      }

      CONTENT_LENGTH_TYPE_REGEXP = /^Content-(?:Type|Length)$/i

      def self.new(app)
        inst = super()
        inst.app = app
        inst
      end

      attr_accessor :async
      alias :async? :async

      def async!
        @async = true
      end

      attr_accessor :app

      def set_headers(response, headers)
        headers.each do |header, value|
          case header
          when CONTENT_TYPE_RESP
            response.set_content_type(value)
          when CONTENT_LENGTH_RESP
            response.set_content_length(value.to_i)
          else
            value.split("\n").each do |v|
              response.add_header(header, v)
            end
          end
        end
      end

      def handle(target, base_request, request, response)
        begin
          env = DEFAULT_RACK_ENV.merge(
            SCRIPT_NAME     => "",
            PATH_INFO       => request.get_path_info,
            REQUEST_URI     => request.getRequestURI,
            REQUEST_METHOD  => request.get_method       || "GET",
            RACK_URL_SCHEME => request.get_scheme       || "http",
            QUERY_STRING    => request.get_query_string || "",
            SERVER_NAME     => request.get_server_name  || "",
            REMOTE_HOST     => request.get_remote_host  || "",
            REMOTE_ADDR     => request.get_remote_addr  || "",
            REMOTE_USER     => request.get_remote_user  || "",
            SERVER_PORT     => request.get_server_port.to_s,
            LOCAL_PORT      => request.get_local_port.to_s,
            RACK_VERSION    => ::Rack::VERSION)

          # Process the content length
          if (content_length = request.get_content_length) >= 0
            env[CONTENT_LENGTH] = content_length.to_s
          else
            env[CONTENT_LENGTH] = "0"
          end

          if (content_type = request.get_content_type)
            env[CONTENT_TYPE] = content_type unless content_type == ''
          end

          request.get_header_names.each do |header|
            next if header =~ CONTENT_LENGTH_TYPE_REGEXP
            value = request.get_header(header)

            header.tr! '-', '_'
            header.upcase!

            header      = "#{HTTP_PREFIX}#{header}"
            env[header] = value unless env.key?(header) || value == ''
          end

          input = request.get_input_stream

          case env['HTTP_CONTENT_ENCODING']
          when 'deflate' then input = InflaterInputStream.new(input)
          when 'gzip'    then input = GZIPInputStream.new(input)
          end

          input = InputStream.new(input)
          env[RACK_INPUT] = input

          env['kirk.async'] = Async.new(self, request, response)

          # Dispatch the request
          status, headers, body = @app.call(env)

          if async?
            env['kirk.async'].suspend(response)
          else
            response.set_status(status.to_i)

            set_headers(response, headers)

            buffer = response.get_output_stream
            body.each do |s|
              buffer.write(s.to_java_bytes)
            end

            body.close if body.respond_to?(:close)
          end
        ensure
          input.recycle if input.respond_to?(:recycle)
          request.set_handled(true)
        end
      end
    end
  end
end
