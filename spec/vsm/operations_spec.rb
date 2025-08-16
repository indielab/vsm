# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::Operations do
  include Async::RSpec::Reactor

  let(:ops) { described_class.new }
  let(:bus) { VSM::AsyncChannel.new }
  let(:children) { { "echo" => FakeEchoTool.new, "slow" => SlowTool.new, "boom" => ErrorTool.new } }

  it "routes tool_call to child and emits tool_result" do
    results = Queue.new
    bus.subscribe { |m| results << m if m.kind == :tool_result }

    msg = VSM::Message.new(kind: :tool_call, payload: { tool: "echo", args: { "text" => "ok" } }, corr_id: "1")
    expect(ops.handle(msg, bus:, children:)).to be true

    out = results.pop
    expect(out.corr_id).to eq("1")
    expect(out.payload).to eq("echo: ok")
  end

  it "runs multiple slow tools in parallel via threads" do
    results = Queue.new
    bus.subscribe { |m| results << m if m.kind == :tool_result }

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    2.times do |i|
      msg = VSM::Message.new(kind: :tool_call, payload: { tool: "slow", args: { "id" => i } }, corr_id: i.to_s)
      ops.handle(msg, bus:, children:)
    end

    # Wait for both results to come back
    msgs = 2.times.map { results.pop }

    ids = msgs.map(&:payload).sort
    expect(ids).to eq(["slow-0", "slow-1"])

    total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    expect(total).to be < 0.6 # proves parallelism vs serial 0.5+
  end

  it "handles tool errors by emitting error result" do
    seen = []
    bus.subscribe { |m| seen << m if m.kind == :tool_result }
    msg = VSM::Message.new(kind: :tool_call, payload: { tool: "boom", args: {} }, corr_id: "x")
    ops.handle(msg, bus:, children:)
    Async { |t| t.sleep 0.05 }
    expect(seen.first.payload).to match(/ERROR: RuntimeError: kapow/)
  end
end

