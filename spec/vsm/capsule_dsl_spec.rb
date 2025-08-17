# frozen_string_literal: true
require "spec_helper"

RSpec.describe "Capsule and DSL" do
  include Async::RSpec::Reactor

  it "builds a capsule with operations & injects governance into tools" do
    gov = FakeGovernance.new
    cap = VSM::DSL::Builder.new(:demo).tap do |b|
      b.identity(klass: VSM::Identity, args: { identity: "demo", invariants: [] })
      b.governance(klass: FakeGovernance, args: {})
      b.coordination(klass: VSM::Coordination)
      b.intelligence(klass: VSM::Intelligence, args: { driver: FakeDriver.new })
      b.operations do
        capsule :echo, klass: FakeEchoTool
      end
      b.monitoring(klass: VSM::Monitoring)
    end.build

    # Every child tool gets governance object injected
    child = cap.children["echo"]
    expect(child.governance).to be_a(VSM::Governance)

    # Bus context exposes operations_children for intelligence
    expect(cap.bus.context[:operations_children].keys).to include("echo")
  end
end

