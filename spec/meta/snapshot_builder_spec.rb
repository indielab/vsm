# frozen_string_literal: true

require "spec_helper"

RSpec.describe VSM::Meta::SnapshotBuilder do
  class SnapshotTestIdentity < VSM::Identity
    def initialize(identity:, invariants: [])
      super
    end
  end

  class SnapshotTestTool < VSM::ToolCapsule
    tool_name "snapshot_test"
    tool_description "Tool for testing snapshot builder"
    tool_schema({ type: "object", properties: {}, required: [] })

    def run(_args)
      "ok"
    end
  end

  let(:capsule) do
    VSM::DSL.define(:snapshot_host) do
      identity     klass: SnapshotTestIdentity, args: { identity: "snapshot_host", invariants: ["stay"] }
      governance   klass: VSM::Governance,     args: {}
      coordination klass: VSM::Coordination,   args: {}
      intelligence klass: VSM::Intelligence,   args: {}
      monitoring   klass: VSM::Monitoring,     args: {}
      operations do
        capsule :snapshot_test, klass: SnapshotTestTool
      end
    end
  end

  let(:snapshot) { described_class.new(root: capsule).call }

  it "captures root capsule metadata" do
    expect(snapshot[:name]).to eq("snapshot_host")
    expect(snapshot[:roles].keys).to include("identity", "governance", "operations")
  end

  it "captures constructor args for roles" do
    expect(snapshot[:roles]["identity"][:constructor_args]).to eq({ identity: "snapshot_host", invariants: ["stay"] })
  end

  it "captures tool child details" do
    tool = snapshot[:operations][:children]["snapshot_test"]
    expect(tool[:kind]).to eq("tool")
    expect(tool[:tool][:name]).to eq("snapshot_test")
    expect(tool[:source_locations].map { _1[:method] }).to include("run")
  end
end

