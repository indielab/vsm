# frozen_string_literal: true
require "vsm"

RSpec.describe VSM do
  include Async::RSpec::Reactor

  it "builds a capsule and routes a tool call" do
    class T < VSM::ToolCapsule
      tool_name "t"; tool_description "d"; tool_schema({ type: "object", properties: {}, required: [] })
      def run(_args) = "ok"
    end

    cap = VSM::DSL.define(:test) do
      identity     klass: VSM::Identity,    args: { identity: "t", invariants: [] }
      governance   klass: VSM::Governance
      coordination klass: VSM::Coordination
      intelligence klass: VSM::Intelligence
      operations do
        capsule :t, klass: T
      end
    end

    # Test operations component directly instead of full capsule
    ops = cap.roles[:operations]
    bus = cap.bus
    children = cap.children
    
    q = Queue.new
    bus.subscribe { |m| q << m if m.kind == :tool_result }
    
    msg = VSM::Message.new(kind: :tool_call, payload: { tool: "t", args: {} }, corr_id: "1")
    expect(ops.handle(msg, bus:, children:)).to be true
    
    result = q.pop
    expect(result.payload).to eq("ok")
  end
end

