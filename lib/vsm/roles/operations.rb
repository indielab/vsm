# frozen_string_literal: true

require_relative "../executors/fiber_executor"
require_relative "../executors/thread_executor"

module VSM
  class Operations
    EXECUTORS = {
      fiber:  Executors::FiberExecutor,
      thread: Executors::ThreadExecutor
    }.freeze

    def observe(bus); end

    def handle(message, bus:, children:, **)
      return false unless message.kind == :tool_call

      name = message.payload[:tool].to_s
      tool_capsule = children.fetch(name) { raise "unknown tool capsule: #{name}" }
      mode = tool_capsule.respond_to?(:execution_mode) ? tool_capsule.execution_mode : :fiber
      executor = EXECUTORS.fetch(mode)

      Async do
        result = executor.call(tool_capsule, message.payload[:args])
        bus.emit Message.new(kind: :tool_result, payload: result, corr_id: message.corr_id, meta: message.meta)
      rescue => e
        bus.emit Message.new(kind: :tool_result, payload: "ERROR: #{e.class}: #{e.message}", corr_id: message.corr_id, meta: message.meta)
      end

      true
    end
  end
end
