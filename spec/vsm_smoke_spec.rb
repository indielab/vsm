# frozen_string_literal: true
require "vsm"

RSpec.describe VSM do
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

    # emit a tool call; ensure tool_result arrives
    q = Queue.new
    cap.bus.subscribe { |m| q << m if m.kind == :tool_result }
    cap.run
    cap.bus.emit VSM::Message.new(kind: :tool_call, payload: { tool: "t", args: {} }, corr_id: "1")
    msg = q.pop
    expect(msg.payload).to eq("ok")
  end
end

