# frozen_string_literal: true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "vsm"
require "vsm/ports/chat_tty"
require "securerandom"

# Demonstrates subclassing ChatTTY to customize the banner and output formatting.

class EchoTool < VSM::ToolCapsule
  tool_name "echo"
  tool_description "Echoes back the provided text"
  tool_schema({ type: "object", properties: { text: { type: "string" } }, required: ["text"] })
  def run(args)
    "you said: #{args["text"]}"
  end
end

class DemoIntelligence < VSM::Intelligence
  def handle(message, bus:, **)
    return false unless message.kind == :user
    if message.payload =~ /\Aecho:\s*(.+)\z/
      bus.emit VSM::Message.new(kind: :tool_call, payload: { tool: "echo", args: { "text" => $1 } }, corr_id: SecureRandom.uuid, meta: message.meta)
    else
      bus.emit VSM::Message.new(kind: :assistant, payload: "Try: echo: hello", meta: message.meta)
    end
    true
  end
end

class FancyTTY < VSM::Ports::ChatTTY
  def banner(io)
    io.puts "\e[95m\n ███  CUSTOM CHAT  ███\n\e[0m"
  end

  def render_out(m)
    case m.kind
    when :assistant_delta
      @streaming = true
      @out.print m.payload
      @out.flush
    when :assistant
      @out.puts unless @streaming
      @streaming = false
    when :tool_call
      @out.puts "\n\e[90m→ calling #{m.payload[:tool]}\e[0m"
    when :tool_result
      @out.puts "\e[92m✓ #{m.payload}\e[0m"
    end
  end
end

cap = VSM::DSL.define(:fancy_chat) do
  identity     klass: VSM::Identity,     args: { identity: "fancy_chat", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: DemoIntelligence
  monitoring   klass: VSM::Monitoring
  operations do
    capsule :echo, klass: EchoTool
  end
end

VSM::Runtime.start(cap, ports: [FancyTTY.new(capsule: cap, prompt: "Me: ")])
