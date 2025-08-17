# frozen_string_literal: true

# A simple tool that echoes text (fiber-safe)
class FakeEchoTool < VSM::ToolCapsule
  tool_name "echo"
  tool_description "Echo back the text"
  tool_schema({ type: "object", properties: { text: { type: "string" } }, required: ["text"] })

  def run(args) = "echo: #{args["text"]}"
end

# A slow tool that sleeps; marks thread mode to allow parallelism
class SlowTool < VSM::ToolCapsule
  tool_name "slow"
  tool_description "Sleep briefly and return id"
  tool_schema({ type: "object", properties: { id: { type: "integer" } }, required: ["id"] })

  def execution_mode = :thread
  def run(args)
    sleep 0.25
    "slow-#{args["id"]}"
  end
end

# A tool that raises
class ErrorTool < VSM::ToolCapsule
  tool_name "boom"
  tool_description "Always raises"
  tool_schema({ type: "object", properties: {}, required: [] })

  def run(_args)
    raise "kapow"
  end
end

# A minimal intelligence that:
# - on :user payload "echo <text>" emits a tool_call to echo
# - on :user payload "slow2" emits two parallel slow calls
# - on :tool_result emits :assistant to finish the turn
class FakeIntelligence < VSM::Intelligence
  def initialize
    @by_session = Hash.new { |h,k| h[k] = { pending: 0 } }
  end

  def handle(message, bus:, **)
    case message.kind
    when :user
      sid = message.meta&.dig(:session_id)
      case message.payload
      when /\Aecho\s+(.+)\z/
        @by_session[sid][:pending] = 1
        bus.emit VSM::Message.new(
          kind: :tool_call,
          payload: { tool: "echo", args: { "text" => Regexp.last_match(1) } },
          corr_id: SecureRandom.uuid,
          meta: { session_id: sid }
        )
        true
      when "slow2"
        @by_session[sid][:pending] = 2
        2.times do |i|
          bus.emit VSM::Message.new(
            kind: :tool_call,
            payload: { tool: "slow", args: { "id" => i } },
            corr_id: "slow-#{i}",
            meta: { session_id: sid }
          )
        end
        true
      when "boom"
        @by_session[sid][:pending] = 1
        bus.emit VSM::Message.new(
          kind: :tool_call,
          payload: { tool: "boom", args: {} },
          corr_id: "boom",
          meta: { session_id: sid }
        )
        true
      else
        bus.emit VSM::Message.new(kind: :assistant, payload: "unknown", meta: message.meta)
        true
      end
    when :tool_result
      sid = message.meta&.dig(:session_id)
      @by_session[sid][:pending] -= 1
      if @by_session[sid][:pending] <= 0
        bus.emit VSM::Message.new(kind: :assistant, payload: "done", meta: { session_id: sid })
      end
      true
    else
      false
    end
  end
end

# A governance that denies writes outside a fake root and requests confirmation for "danger"
class FakeGovernance < VSM::Governance
  attr_reader :confirm_requests

  def initialize(root: Dir.pwd)
    @root = File.expand_path(root)
    @confirm_requests = []
  end

  def enforce(message)
    if message.kind == :tool_call && message.payload[:tool] == "echo"
      if (txt = message.payload.dig(:args, "text")) && txt.include?("danger")
        @confirm_requests << txt
        message.meta ||= {}
        message.meta[:needs_confirm] = true
        # In a real system Governance would emit a :confirm_request and await :confirm_response.
        # For tests we simply tag it and pass it through.
      end
    end
    yield message
  end
end

# Identity spy that records alerts
class SpyIdentity < VSM::Identity
  attr_reader :alerts
  def initialize(identity: "spy", invariants: [])
    super(identity:, invariants:)
    @alerts = []
  end
  def alert(message)
    @alerts << message
  end
end

# A fake driver for testing that doesn't make real API calls
class FakeDriver
  def run!(conversation:, tools:, policy: {}, &emit)
    # Simple test driver that just emits a basic response
    yield(:assistant_final, "test response") if block_given?
  end
end

