require 'rack'

module Kirk
  # Make sure that the version of JRuby is new enough
  unless (JRUBY_VERSION.split('.')[0..2].map(&:to_i) <=> [1, 6, 0]) >= 0
    raise "Kirk requires JRuby 1.6.0 RC 1 or greater. This is due to "   \
          "a bug that was fixed in the 1.6 line but not backported to "  \
          "older versions of JRuby. If you want to use Kirk with older " \
          "versions of JRuby, bug headius."
  end

  require 'java'
  require 'kirk/version'

  autoload :Client, 'kirk/client'
  autoload :Jetty,  'kirk/jetty'
  autoload :Native, 'kirk/native'
  autoload :Server, 'kirk/server'

  java_import "java.net.InetSocketAddress"
  java_import "java.nio.ByteBuffer"

  java_import "java.util.concurrent.AbstractExecutorService"
  java_import "java.util.concurrent.ExecutorCompletionService"
  java_import "java.util.concurrent.LinkedBlockingQueue"
  java_import "java.util.concurrent.TimeUnit"
  java_import "java.util.concurrent.ThreadPoolExecutor"

  java_import "java.util.logging.Logger"
  java_import "java.util.logging.Level"
  java_import "java.util.logging.ConsoleHandler"

  def self.sub_process?
    !!defined?(Kirk::PARENT_VERSION)
  end

  # Configure the logger
  def self.logger
    @logger ||= begin
      logger = Logger.get_logger("org.eclipse.jetty.util.log")

      unless sub_process?
        logger.set_use_parent_handlers(false)
        logger.add_handler logger_handler
      end

      logger
    end
  end

  def self.logger_handler
    ConsoleHandler.new.tap do |handler|
      handler.set_output_stream(java::lang::System.out)
      handler.set_formatter(Native::LogFormatter.new)
    end
  end
end
