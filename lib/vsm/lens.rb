# frozen_string_literal: true
require_relative "lens/event_hub"
require_relative "lens/server"
require "rack/handler/webrick"

module VSM
  module Lens
    def self.attach!(capsule, host: "127.0.0.1", port: 9292, token: nil)
      hub = EventHub.new

      # Subscribe to the capsule bus and publish every message
      capsule.bus.subscribe { |msg| hub.publish(msg) }

      # Optionally: also mirror to Monitoring ledger if you want
      # (Your existing Monitoring already logs by subscribing to the bus.)

      server = Server.new(hub:, token:)
      Thread.new do
        Rack::Handler::WEBrick.run(
          server.rack_app,
          Host: host, Port: port,
          AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        )
      end
    end
  end
end

