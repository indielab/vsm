# frozen_string_literal: true

# Example: OpenAI streaming demo (no tools)
#
# Usage:
#   OPENAI_API_KEY=... AIRB_MODEL=gpt-4o-mini ruby examples/02_openai_streaming.rb
#   VSM_DEBUG_STREAM=1 to see low-level logs

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "securerandom"
require "vsm"

MODEL = ENV["AIRB_MODEL"] || "gpt-4o-mini"

driver = VSM::Drivers::OpenAI::AsyncDriver.new(
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model: MODEL
)

system_prompt = <<~PROMPT
  You are a concise assistant. Answer briefly.
PROMPT

cap = VSM::DSL.define(:openai_stream_demo) do
  identity     klass: VSM::Identity,     args: { identity: "openai_stream_demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: driver, system_prompt: system_prompt }
  operations   klass: VSM::Operations
  monitoring   klass: VSM::Monitoring
end

if ENV["VSM_LENS"] == "1"
  VSM::Lens.attach!(cap, port: (ENV["VSM_LENS_PORT"] || 9292).to_i, token: ENV["VSM_LENS_TOKEN"]) rescue nil
end

class StreamTTY < VSM::Port
  def should_render?(message)
    [:assistant_delta, :assistant, :tool_result, :tool_call].include?(message.kind)
  end

  def loop
    sid = SecureRandom.uuid
    puts "openai streaming demo — type to chat (Ctrl-C to exit)"
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
      # Stream without newline
      print msg.payload
      $stdout.flush
    when :assistant
      puts "" # end the line
      puts msg.payload.to_s unless msg.payload.to_s.empty?
      puts "(turn #{msg.meta&.dig(:turn_id)})"
    when :tool_result
      puts "\nTool> #{msg.payload}"
    when :tool_call
      puts "\nTool? #{msg.payload[:tool]}(#{msg.corr_id}) #{msg.payload[:args].inspect}"
    end
  end
end

VSM::Runtime.start(cap, ports: [StreamTTY.new(capsule: cap)])


