# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "vsm"
require "vsm/dsl_mcp"
require "vsm/ports/chat_tty"

# Example: Use an LLM driver (OpenAI) to automatically call tools exposed by an MCP server.
#
# Prereqs:
#   - OPENAI_API_KEY must be set
#   - An MCP server available on your PATH, e.g. `claude mcp serve`
#
# Usage:
#   OPENAI_API_KEY=... AIRB_MODEL=gpt-4o-mini ruby examples/09_mcp_with_llm_calls.rb
#   Type a question; the model will choose tools from the reflected MCP server.

MODEL = ENV["AIRB_MODEL"] || "gpt-4o-mini"

driver = VSM::Drivers::OpenAI::AsyncDriver.new(
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model: MODEL
)

system_prompt = <<~PROMPT
  You are a helpful assistant. You have access to the listed tools.
  When a tool can help, call it with appropriate JSON arguments.
  Keep final answers concise.
PROMPT

cap = VSM::DSL.define(:mcp_with_llm) do
  identity     klass: VSM::Identity,     args: { identity: "mcp_with_llm", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: driver, system_prompt: system_prompt }
  monitoring   klass: VSM::Monitoring
  operations do
    # Reflect tools from an external MCP server (e.g., Claude Code).
    # If your server requires strict LSP framing, run with VSM_MCP_LSP=1.
    # You can also prefix names to avoid collisions: prefix: "claude_"
    mcp_server :claude, cmd: ["claude", "mcp", "serve"]
  end
end

banner = ->(io) do
  io.puts "\e[96mLLM + MCP tools\e[0m — Ask a question; model may call tools."
end

VSM::Runtime.start(cap, ports: [VSM::Ports::ChatTTY.new(capsule: cap, banner: banner, prompt: "You> ")])

