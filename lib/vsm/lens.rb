# lib/vsm/lens.rb
# frozen_string_literal: true
require_relative "lens/event_hub"
require_relative "lens/server"

module VSM
  module Lens
    # Starts a tiny Rack server (Puma or WEBrick) and streams events via SSE.
    # Returns the EventHub so other lenses (e.g., TUI) can also subscribe.
    def self.attach!(capsule, host: "127.0.0.1", port: 9292, token: nil)
      hub = EventHub.new

      # Mirror all bus messages to the hub:
      capsule.bus.subscribe { |msg| hub.publish(msg) }

      server = Server.new(hub: hub, token: token)

      Thread.new do
        app = server.rack_app

        # Prefer Puma if present:
        if try_run_puma(app, host, port)
          # ok
        elsif try_run_webrick(app, host, port)
          # ok
        else
          warn <<~MSG
            vsm-lens: no Rack handler found. Install one of:
              - `bundle add puma`
              - or `bundle add webrick`
            Then re-run with VSM_LENS=1.
          MSG
        end
      end

      hub
    end

    def self.try_run_puma(app, host, port)
      begin
        require "rack/handler/puma"
      rescue LoadError
        return false
      end
      Thread.new do
        Rack::Handler::Puma.run(app, Host: host, Port: port, Silent: true)
      end
      true
    rescue => e
      warn "vsm-lens: Puma failed to start: #{e.class}: #{e.message}"
      false
    end

    def self.try_run_webrick(app, host, port)
      begin
        require "webrick"                 # provide the server
        require "rack/handler/webrick"    # rack adapter (Rack 3 loads this if webrick gem is present)
      rescue LoadError
        return false
      end
      Thread.new do
        Rack::Handler::WEBrick.run(
          app,
          Host: host, Port: port,
          AccessLog: [],
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        )
      end
      true
    rescue => e
      warn "vsm-lens: WEBrick failed to start: #{e.class}: #{e.message}"
      false
    end
  end
end

