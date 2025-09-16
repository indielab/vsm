# frozen_string_literal: true

require "thread"

module VSM
  module Meta
    class SnapshotCache
      def initialize(builder)
        @builder = builder
        @mutex = Mutex.new
        @snapshot = nil
      end

      def fetch
        @mutex.synchronize do
          @snapshot ||= { generated_at: Time.now.utc, data: @builder.call }
        end
      end

      def invalidate!
        @mutex.synchronize { @snapshot = nil }
      end
    end
  end
end
