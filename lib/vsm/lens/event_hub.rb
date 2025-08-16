# frozen_string_literal: true
require "json"
require "time"
require "securerandom"

module VSM
  module Lens
    class EventHub
      DEFAULT_BUFFER = 500

      def initialize(buffer_size: DEFAULT_BUFFER)
        @subs = []                 # Array of SizedQueue
        @mutex = Mutex.new
        @buffer = []
        @buffer_size = buffer_size
      end

      def publish(message)
        event = format_event(message)
        @mutex.synchronize do
          @buffer << event
          @buffer.shift(@buffer.size - @buffer_size) if @buffer.size > @buffer_size
          @subs.each { |q| try_push(q, event) }
        end
      end

      def subscribe
        q = SizedQueue.new(100)
        snapshot = nil
        @mutex.synchronize do
          @subs << q
          snapshot = @buffer.dup
        end
        [q, snapshot]
      end

      def unsubscribe(queue)
        @mutex.synchronize { @subs.delete(queue) }
      end

      private

      def try_push(queue, event)
        queue.push(event)
      rescue ThreadError
        # queue full; drop event to avoid blocking the pipeline
      end

      def format_event(msg)
        {
          id:        SecureRandom.uuid,
          ts:        Time.now.utc.iso8601(6),
          kind:      msg.kind,
          path:      msg.path,
          corr_id:   msg.corr_id,
          meta:      msg.meta,
          # Small preview to avoid huge payloads; the UI can request details later if you add a /event/:id endpoint
          payload:   preview(msg.payload)
        }
      end

      def preview(payload)
        case payload
        when String
          payload.bytesize > 2_000 ? payload.byteslice(0, 2_000) + "… (truncated)" : payload
        else
          payload
        end
      end
    end
  end
end

