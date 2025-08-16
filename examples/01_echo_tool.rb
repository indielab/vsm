# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "vsm"

class EchoTool < VSM::ToolCapsule
  tool_name "echo"
  tool_description "Echoes a message"
  tool_schema({ type: "object", properties: { text: { type: "string" } }, required: ["text"] })

  def run(args)
    "you said: #{args["text"]}"
  end
end

# Minimal “intelligence” that triggers a tool when user types "echo: ..."
class DemoIntelligence < VSM::Intelligence
  def handle(message, bus:, **)
    case message.kind
    when :user
      if message.payload =~ /\Aecho:\s*(.+)\z/
        bus.emit VSM::Message.new(kind: :tool_call, payload: { tool: "echo", args: { "text" => $1 } }, corr_id: SecureRandom.uuid, meta: message.meta)
      else
        bus.emit VSM::Message.new(kind: :assistant, payload: "Try: echo: hello", meta: message.meta)
      end
      true
    when :tool_result
      # Complete the turn after tool execution
      bus.emit VSM::Message.new(kind: :assistant, payload: "(done)", meta: message.meta)
      true
    else
      false
    end
  end
end

cap = VSM::DSL.define(:demo) do
  identity    klass: VSM::Identity,    args: { identity: "demo", invariants: [] }
  governance  klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: DemoIntelligence
  monitoring  klass: VSM::Monitoring
  operations do
    capsule :echo, klass: EchoTool
  end
end

# Simple CLI port
class StdinPort < VSM::Port
  def loop
    sid = SecureRandom.uuid
    print "You: "
    while (line = $stdin.gets&.chomp)
      @capsule.bus.emit VSM::Message.new(kind: :user, payload: line, meta: { session_id: sid })
      @capsule.roles[:coordination].wait_for_turn_end(sid)
      print "You: "
    end
  end

  def render_out(msg)
    case msg.kind
    when :assistant
      puts "\nBot: #{msg.payload}"
    when :tool_result
      puts "\nTool> #{msg.payload}"
    end
  end
end

VSM::Runtime.start(cap, ports: [StdinPort.new(capsule: cap)])

