# frozen_string_literal: true
module VSM
  class Coordination
    def initialize
      @queue = []
      @floor_by_session = nil
      @turn_waiters = {} # session_id => Async::Queue
    end

    def observe(bus)
      bus.subscribe { |m| stage(m) }
    end

    def stage(message) = (@queue << message)

    def drain(bus)
      return if @queue.empty?
      @queue.sort_by! { order(_1) }
      @queue.shift(@queue.size).each do |msg|
        yield msg
        if msg.kind == :assistant && (sid = msg.meta&.dig(:session_id)) && @turn_waiters[sid]
          @turn_waiters[sid].enqueue(:done)
        end
      end
    end

    def grant_floor!(session_id) = (@floor_by_session = session_id)

    def wait_for_turn_end(session_id)
      q = (@turn_waiters[session_id] ||= Async::Queue.new)
      q.dequeue
    end

    def order(m)
      base =
        case m.kind
        when :user            then 0
        when :tool_result     then 1
        when :plan            then 2
        when :assistant_delta then 3
        when :assistant       then 4
        else 9
        end
      sid = m.meta&.dig(:session_id)
      sid == @floor_by_session ? base - 1 : base
    end
  end
end
