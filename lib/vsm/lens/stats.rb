# frozen_string_literal: true
require "time"

module VSM
  module Lens
    class Stats
      def initialize(hub:, capsule:)
        @sessions = Hash.new { |h,k| h[k] = { count: 0, last: nil, kinds: Hash.new(0) } }
        @kinds    = Hash.new(0)
        @capsule  = capsule

        queue, snapshot = hub.subscribe
        snapshot.each { |ev| ingest(ev) }

        @thread = Thread.new do
          loop do
            ev = queue.pop
            ingest(ev)
          end
        end
      end

      def state
        {
          ts: Time.now.utc.iso8601(6),
          sessions: sort_sessions(@sessions),
          kinds: @kinds.dup,
          tools: tool_inventory,
          budgets: {
            limits: @capsule.homeostat.limits,
            usage:  @capsule.homeostat.usage_snapshot
          }
        }
      end

      private

      def ingest(ev)
        @kinds[ev[:kind]] += 1
        sid = ev.dig(:meta, :session_id)
        return unless sid
        @sessions[sid][:count] += 1
        @sessions[sid][:last]   = ev[:ts]
        @sessions[sid][:kinds][ev[:kind]] += 1
      end

      def sort_sessions(h)
        h.sort_by { |_sid, s| s[:last].to_s }.reverse.to_h
      end

      def tool_inventory
        ops = @capsule.bus.context[:operations_children] || {}
        ops.keys.sort
      end
    end
  end
end

