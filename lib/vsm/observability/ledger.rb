# frozen_string_literal: true
require "json"
require "time"

module VSM
  class Monitoring
    LOG = File.expand_path(".vsm.log.jsonl", Dir.pwd)

    def observe(bus)
      bus.subscribe do |msg|
        event = {
          ts: Time.now.utc.iso8601,
          kind: msg.kind,
          path: msg.path,
          corr_id: msg.corr_id,
          meta: msg.meta
        }
        File.open(LOG, "a") { |f| f.puts(event.to_json) } rescue nil
      end
    end

    def handle(*) = false
  end
end

