# frozen_string_literal: true

# Example: Anthropic streaming demo (no tools)

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "securerandom"
require "vsm"

MODEL = ENV["AIRB_MODEL"] || "claude-sonnet-4-0"

driver = VSM::Drivers::Anthropic::AsyncDriver.new(
  api_key: ENV.fetch("ANTHROPIC_API_KEY"),
  model: MODEL,
  streaming: true,
  transport: :nethttp
)

system_prompt = "You are a concise assistant. Answer briefly."

cap = VSM::DSL.define(:anthropic_stream_demo) do
  identity     klass: VSM::Identity,     args: { identity: "anthropic_stream_demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: driver, system_prompt: system_prompt }
  operations   klass: VSM::Operations
  monitoring   klass: VSM::Monitoring
end

class StreamTTY < VSM::Port
  def should_render?(message)
    [:assistant_delta, :assistant].include?(message.kind) || message.kind == :tool_calls
  end

  def loop
    sid = SecureRandom.uuid
    puts "anthropic streaming demo — type to chat (Ctrl-C to exit)"
    print "You: "
    while (line = $stdin.gets&.chomp)
      @capsule.bus.emit VSM::Message.new(kind: :user, payload: line, meta: { session_id: sid })
      @capsule.roles[:coordination].wait_for_turn_end(sid)
      print "You: "
    end
  end

  def render_out(msg)
    case msg.kind
    when :assistant_delta
      print msg.payload
      $stdout.flush
    when :assistant
      puts ""
      puts "(turn #{msg.meta&.dig(:turn_id)})"
    when :tool_calls
      puts "\n(tool_calls #{msg.payload&.size || 0})"
    end
  end
end

VSM::Runtime.start(cap, ports: [StreamTTY.new(capsule: cap)])


