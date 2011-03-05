# Only require jars if in the "master" process
unless Kirk.sub_process?
  require "kirk/jetty/servlet-api-2.5"

  %w(util http io continuation server client).each do |mod|
    require "kirk/jetty/jetty-#{mod}-7.3.0.v20110203"
  end
end

module Kirk
  module Jetty
    # Gimme Jetty
    java_import "org.eclipse.jetty.client.HttpClient"
    java_import "org.eclipse.jetty.client.HttpExchange"
    java_import "org.eclipse.jetty.client.ContentExchange"

    java_import "org.eclipse.jetty.io.ByteArrayBuffer"

    java_import "org.eclipse.jetty.server.nio.SelectChannelConnector"
    java_import "org.eclipse.jetty.server.handler.AbstractHandler"
    java_import "org.eclipse.jetty.server.handler.ContextHandler"
    java_import "org.eclipse.jetty.server.handler.ContextHandlerCollection"
    java_import "org.eclipse.jetty.server.Server"

    java_import "org.eclipse.jetty.util.component.LifeCycle"
    java_import "org.eclipse.jetty.util.log.Log"
    java_import "org.eclipse.jetty.util.log.JavaUtilLog"

    java_import "org.eclipse.jetty.continuation.ContinuationSupport"

    Log.set_log Jetty::JavaUtilLog.new unless Kirk.sub_process?
  end
end
