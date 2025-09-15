# frozen_string_literal: true

# Example: Anthropic tool-calling demo (list_files/read_file)

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "securerandom"
require "vsm"

MODEL = ENV["AIRB_MODEL"] || "claude-sonnet-4-0"

class ListFiles < VSM::ToolCapsule
  tool_name "list_files"
  tool_description "List files in a directory"
  tool_schema({ type: "object", properties: { path: { type: "string" } }, required: [] })
  def run(args)
    path = args["path"].to_s.strip
    path = "." if path.empty?
    Dir.children(path).sort.take(200).join("\n")
  rescue => e
    "ERROR: #{e.class}: #{e.message}"
  end
end

class ReadFile < VSM::ToolCapsule
  tool_name "read_file"
  tool_description "Read a small text file"
  tool_schema({ type: "object", properties: { path: { type: "string" } }, required: ["path"] })
  def run(args)
    path = args["path"].to_s
    raise "path required" if path.empty?
    raise "too large" if File.size(path) > 200_000
    File.read(path)
  rescue => e
    "ERROR: #{e.class}: #{e.message}"
  end
end

driver = VSM::Drivers::Anthropic::AsyncDriver.new(
  api_key: ENV.fetch("ANTHROPIC_API_KEY"),
  model: MODEL
)

system_prompt = <<~PROMPT
  You are a coding assistant with two tools: list_files and read_file.
  Prefer to call tools when appropriate. Keep answers brief.
PROMPT

cap = VSM::DSL.define(:anthropic_tools_demo) do
  identity     klass: VSM::Identity,     args: { identity: "anthropic_tools_demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: driver, system_prompt: system_prompt }
  monitoring   klass: VSM::Monitoring
  operations do
    capsule :list_files, klass: ListFiles
    capsule :read_file,  klass: ReadFile
  end
end

class ToolTTY < VSM::Port
  def should_render?(message)
    [:assistant_delta, :assistant, :tool_result, :tool_call].include?(message.kind)
  end

  def loop
    sid = SecureRandom.uuid
    puts "anthropic tools demo — type to chat (Ctrl-C to exit)"
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
    when :tool_call
      puts "\nTool? #{msg.payload[:tool]}(#{msg.corr_id})"
    when :tool_result
      puts "\nTool> (completed)"
    end
  end
end

VSM::Runtime.start(cap, ports: [ToolTTY.new(capsule: cap)])

