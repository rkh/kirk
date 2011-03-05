module Kirk
  class Server
    class Async
      attr_reader :handler, :response
      def initialize(handler, request, response)
        @handler      = handler
        @response     = response
        @buffer       = response.get_output_stream
        @continuation = Jetty::ContinuationSupport.getContinuation(request)
      end

      def start!
        handler.async!
        self
      end

      def suspend(response)
        @continuation.suspend(response)
      end

      def respond(status, headers, body)
        if status
          response.set_status(status)
        end

        if headers
          handler.set_headers(response, headers)
        end

        if body
          @buffer.write(body.to_java_bytes)
        end

        if status.nil? and headers.nil? and body.nil?
          @continuation.complete
        end
      end
    end
  end
end
