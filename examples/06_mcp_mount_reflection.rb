# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "vsm"
require "vsm/dsl_mcp"
require "vsm/ports/chat_tty"
require "securerandom"

# This example mounts a remote MCP server (we use example 05 as the server)
# and exposes its tools locally via dynamic reflection. Type: echo: hello

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

server_cmd = "ruby #{File.expand_path("05_mcp_server_and_chattty.rb", __dir__)}"

cap = VSM::DSL.define(:mcp_mount_demo) do
  identity     klass: VSM::Identity,     args: { identity: "mcp_mount_demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: DemoIntelligence
  monitoring   klass: VSM::Monitoring
  operations do
    # Reflect the remote server's tools; include only :echo and expose as local name "echo"
    mcp_server :demo_server, cmd: server_cmd, include: %w[echo]
  end
end

banner = ->(io) { io.puts "\e[96mMCP mount demo\e[0m — type 'echo: hi' (Ctrl-C to exit)" }
VSM::Runtime.start(cap, ports: [VSM::Ports::ChatTTY.new(capsule: cap, banner: banner)])
