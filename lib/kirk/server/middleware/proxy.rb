module Kirk
  class Server
    module Middleware
      class ProxyHandler
        attr_reader :async

        def initialize(async)
          @async = async
        end

        def on_response_body(response, chunk)
          async.respond(nil, nil, chunk)
        end

        def on_response_head(response)
          async.respond(response.status, response.headers, nil)
        end

        def on_response_complete(response)
          async.respond(nil, nil, nil)
        end
      end

      class Proxy
        DO_NOT_PROXY_HEADERS = %w{proxy-connection connection keep-alive transfer-encoding
                                  te trailer proxy-authorization proxy-authenticate upgrade}

        def initialize(app)
          @app = app
        end

        def call(env)
          async = env["kirk.async"].start!
          handler = ProxyHandler.new(async)
          request = env["kirk.request"]
          method = env["REQUEST_METHOD"]

          headers = fetch_headers(request)

          uri = env["PATH_INFO"][1..-1]
          uri += "?#{env["QUERY_STRING"]}" unless env["QUERY_STRING"].nil? || env["QUERY_STRING"] == ""

          response = Kirk::Client.request(method, uri, handler, env["rack.input"], headers)

          nil
        end

        def fetch_headers(request)
          headers = {}
          connection_header = nil
          request.get_header_names.each do |name|
            value = request.get_header(name)

            name = name.downcase
            if name == "connection"
              connection_header = value.downcase
              next
            elsif name == connection_header || DO_NOT_PROXY_HEADERS.include?(name)
              next
            end

            headers[name] = request.get_header(name)
          end

          headers
        end
      end
    end
  end
end
