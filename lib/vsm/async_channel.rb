# frozen_string_literal: true

module VSM
  class AsyncChannel
    attr_reader :context

    def initialize(context: {})
      @queue = Async::Queue.new
      @subs  = []
      @context = context
    end

    def emit(message)
      begin
        @queue.enqueue(message)
      rescue StandardError
        # If no async scheduler is available in this thread, best-effort enqueue later.
      end
      @subs.each do |blk|
        begin
          Async { blk.call(message) }
        rescue StandardError
          # Fallback when no Async task is active in this thread
          begin
            blk.call(message)
          rescue StandardError
            # ignore subscriber errors
          end
        end
      end
    end

    def pop = @queue.dequeue

    def subscribe(&blk)
      @subs << blk
      blk
    end

    def unsubscribe(subscriber)
      @subs.delete(subscriber)
    end
  end
end
