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
      @queue.enqueue(message)
      @subs.each { |blk| Async { blk.call(message) } }
    end

    def pop = @queue.dequeue
    def subscribe(&blk) = @subs << blk
  end
end
