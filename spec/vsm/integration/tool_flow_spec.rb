# frozen_string_literal: true
require "spec_helper"

RSpec.describe "End-to-end flow" do
  include Async::RSpec::Reactor

  let(:capsule) do
    VSM::DSL.define(:demo) do
      identity     klass: VSM::Identity,     args: { identity: "demo", invariants: [] }
      governance   klass: FakeGovernance,    args: {}
      coordination klass: VSM::Coordination
      intelligence klass: FakeIntelligence
      monitoring   klass: VSM::Monitoring
      operations do
        capsule :echo, klass: FakeEchoTool
        capsule :slow, klass: SlowTool
        capsule :boom, klass: ErrorTool
      end
    end
  end

  it "completes an echo turn and signals turn-end to coordination" do
    sid = "s1"
    capsule.run

    out = []
    capsule.bus.subscribe { |m| out << m.kind }

    capsule.bus.emit VSM::Message.new(kind: :user, payload: "echo hello", meta: { session_id: sid })
    capsule.roles[:coordination].wait_for_turn_end(sid)

    expect(out).to include(:tool_call, :tool_result, :assistant)
  end

  it "runs two slow tools in parallel and finishes one turn" do
    sid = "s2"
    capsule.run
    out = []
    capsule.bus.subscribe { |m| out << [m.kind, m.corr_id] if [:tool_result, :assistant].include?(m.kind) }

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    capsule.bus.emit VSM::Message.new(kind: :user, payload: "slow2", meta: { session_id: sid })
    capsule.roles[:coordination].wait_for_turn_end(sid)
    total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    # We expect two tool_results, any order, then an assistant
    kinds = out.map(&:first)
    expect(kinds.count { |k| k == :tool_result }).to eq(2)
    expect(kinds.last).to eq(:assistant)
    expect(total).to be < 0.5 # parallel vs serial ~0.5s
  end

  it "propagates tool errors but still completes the turn" do
    sid = "s3"
    capsule.run
    seen = []
    capsule.bus.subscribe { |m| seen << m if [:tool_result, :assistant].include?(m.kind) }

    capsule.bus.emit VSM::Message.new(kind: :user, payload: "boom", meta: { session_id: sid })
    capsule.roles[:coordination].wait_for_turn_end(sid)

    tr = seen.find { |m| m.kind == :tool_result }
    expect(tr.payload).to match(/ERROR: RuntimeError: kapow/)
    expect(seen.last.kind).to eq(:assistant)
  end
end

