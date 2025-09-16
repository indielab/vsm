# frozen_string_literal: true

# Demo: use OpenAI tool-calling to let an LLM inspect the running capsule via
# the read-only meta tools. Set OPENAI_API_KEY (and optionally AIRB_MODEL) then:
#   bundle exec ruby examples/10_meta_read_only.rb
# Ask things like "What can you do?" or "Explain meta_demo_tool" and the model
# will call the meta tools to gather context before replying.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "securerandom"
require "vsm"

MODEL = ENV["AIRB_MODEL"] || "gpt-4o-mini"
API_KEY = ENV["OPENAI_API_KEY"] or abort "OPENAI_API_KEY required for this demo"

class MetaDemoTool < VSM::ToolCapsule
  tool_name "meta_demo_tool"
  tool_description "Simple tool included alongside meta tools"
  tool_schema({ type: "object", properties: {}, additionalProperties: false })

  def run(_args)
    "hello from demo tool"
  end
end

driver = VSM::Drivers::OpenAI::AsyncDriver.new(api_key: API_KEY, model: MODEL)

SYSTEM_PROMPT = <<~PROMPT
  You are the steward of a VSM capsule. You have access to built-in reflection
  tools that describe the organism and its operations:
    - meta_summarize_self: overview of the current capsule and its roles
    - meta_list_tools: list available tools with schemas
    - meta_explain_tool: show implementation details for a named tool
    - meta_explain_role: show capsule-specific details and code for a VSM role
  When the user asks about capabilities, available tools, or how something
  works, call the appropriate meta_* tool first, then respond with a clear,
  human-friendly summary that cites relevant tool names. Be concise but
  complete.
PROMPT

cap = VSM::DSL.define(:meta_demo_llm) do
  identity     klass: VSM::Identity,     args: { identity: "meta_demo_llm", invariants: [] }
  governance   klass: VSM::Governance,   args: {}
  coordination klass: VSM::Coordination, args: {}
  intelligence klass: VSM::Intelligence, args: { driver: driver, system_prompt: SYSTEM_PROMPT }
  monitoring   klass: VSM::Monitoring,   args: {}
  operations do
    meta_tools
    capsule :meta_demo_tool, klass: MetaDemoTool
  end
end

ports = [VSM::Ports::ChatTTY.new(capsule: cap, banner: ->(io) { io.puts "Meta demo ready. Try asking 'What can you do?'" })]

VSM::Runtime.start(cap, ports: ports)
