# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "json"
require "securerandom"
require "vsm"
require "vsm/dsl_mcp"
require "vsm/ports/chat_tty"

# Example: Connect to an external MCP server (Claude Code)
#
# Prereqs:
#   - Install Claude CLI and log in.
#   - Ensure `claude mcp serve` works in your shell.
#
# IMPORTANT: Many MCP servers (including Claude) use LSP-style Content-Length
# framing over stdio. The minimal transport in this repo currently uses NDJSON
# (one JSON per line). If this example hangs or fails, it's due to framing
# mismatch; swap the transport to LSP framing in lib/vsm/mcp/jsonrpc.rb.
#
# Usage:
#   ruby examples/07_connect_claude_mcp.rb
#   Then type:
#     list
#     call: some_tool {"arg1":"value"}
#
# This example avoids requiring any LLM API keys by letting you call tools manually
# via a simple chat convention.

# Intelligence that recognizes two commands:
# - "list" → prints available tools
# - "call: NAME {json}" → invokes the reflected tool with JSON args
class ManualMCPIntelligence < VSM::Intelligence
  def handle(message, bus:, **)
    return false unless message.kind == :user
    line = message.payload.to_s.strip
    if line == "list"
      # Inspect operations children for tool descriptors
      ops = bus.context[:operations_children] || {}
      tools = ops.values.select { _1.respond_to?(:tool_descriptor) }.map { _1.tool_descriptor.name }
      bus.emit VSM::Message.new(kind: :assistant, payload: tools.any? ? "tools: #{tools.join(", ")}" : "(no tools)", meta: message.meta)
      return true
    elsif line.start_with?("call:")
      if line =~ /\Acall:\s*(\S+)\s*(\{.*\})?\z/
        tool = $1
        json = $2
        args = json ? (JSON.parse(json) rescue {}) : {}
        bus.emit VSM::Message.new(kind: :tool_call, payload: { tool: tool, args: args }, corr_id: SecureRandom.uuid, meta: message.meta)
        return true
      else
        bus.emit VSM::Message.new(kind: :assistant, payload: "usage: call: NAME {json}", meta: message.meta)
        return true
      end
    else
      bus.emit VSM::Message.new(kind: :assistant, payload: "Commands: list | call: NAME {json}", meta: message.meta)
      return true
    end
  end
end

cap = VSM::DSL.define(:claude_mcp_client) do
  identity     klass: VSM::Identity,     args: { identity: "claude_mcp_client", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: ManualMCPIntelligence
  monitoring   klass: VSM::Monitoring
  operations do
    # Reflect all available tools from the external server.
    # Tip: if tool names collide with locals, use prefix: "claude_".
    mcp_server :claude, cmd: ["claude", "mcp", "serve"]
  end
end

banner = ->(io) do
  io.puts "\e[96mMCP client (Claude)\e[0m"
  io.puts "Type 'list' or 'call: NAME {json}'"
end

VSM::Runtime.start(cap, ports: [VSM::Ports::ChatTTY.new(capsule: cap, banner: banner, prompt: "You> ")])
