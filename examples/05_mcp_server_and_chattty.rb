# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "vsm"
require "securerandom"
require "vsm/ports/chat_tty"
require "vsm/ports/mcp/server_stdio"

# A simple local tool we can expose to both ChatTTY and MCP stdio.
class EchoTool < VSM::ToolCapsule
  tool_name "echo"
  tool_description "Echoes back the provided text"
  tool_schema({ type: "object", properties: { text: { type: "string" } }, required: ["text"] })
  def run(args)
    "you said: #{args["text"]}"
  end
end

# Minimal intelligence that triggers the echo tool when user types: echo: ...
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
      bus.emit VSM::Message.new(kind: :assistant, payload: "(done)", meta: message.meta)
      true
    else
      false
    end
  end
end

cap = VSM::DSL.define(:demo_mcp_server_and_chat) do
  identity     klass: VSM::Identity,     args: { identity: "demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: DemoIntelligence
  monitoring   klass: VSM::Monitoring
  operations do
    capsule :echo, klass: EchoTool
  end
end

# Run both ports together: MCP stdio (machine) + ChatTTY (human).
banner = ->(io) { io.puts "\e[96mVSM demo\e[0m — type 'echo: hi' (Ctrl-C to exit)" }
ports = [VSM::Ports::MCP::ServerStdio.new(capsule: cap)]
if $stdout.tty?
  # Only enable interactive ChatTTY when attached to a TTY to avoid
  # interfering when this example is spawned as a background MCP server.
  begin
    tty = File.open("/dev/tty", "r+")
  rescue StandardError
    tty = nil
  end
  ports << VSM::Ports::ChatTTY.new(capsule: cap, banner: banner, input: tty, output: tty)
end

VSM::Runtime.start(cap, ports: ports)
