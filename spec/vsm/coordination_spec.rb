# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::Coordination do
  include Async::RSpec::Reactor

  let(:coord) { described_class.new }
  let(:bus)   { VSM::AsyncChannel.new }

  it "orders messages and signals turn end on :assistant" do
    coord.observe(bus)
    sid = "s1"
    m_user  = VSM::Message.new(kind: :user, payload: "hi", meta: { session_id: sid })
    m_toolr = VSM::Message.new(kind: :tool_result, payload: "ok", meta: { session_id: sid })
    m_asst  = VSM::Message.new(kind: :assistant, payload: "done", meta: { session_id: sid })

    # All async operations need to be inside async context
    seq = []
    Async do |task|
      # Manually stage messages since observe no longer auto-stages
      coord.stage(m_toolr)
      coord.stage(m_asst)
      coord.stage(m_user)

      coord.drain(bus) { |m| seq << m.kind }
      expect(seq).to eq([:user, :tool_result, :assistant])

      # Set up waiter before staging assistant message that will signal it
      task.async do
        coord.wait_for_turn_end(sid)
        seq << :unblocked
      end
      
      # Stage another assistant message to trigger the turn-end signal
      coord.stage(VSM::Message.new(kind: :assistant, payload: "final", meta: { session_id: sid }))
      coord.drain(bus) { |_| }
      task.sleep 0.05
      expect(seq).to include(:unblocked)
    end
  end

  it "gives floor priority" do
    coord.grant_floor!("floor")
    m1 = VSM::Message.new(kind: :assistant, meta: { session_id: "other" })
    m2 = VSM::Message.new(kind: :assistant, meta: { session_id: "floor" })
    coord.stage(m1)
    coord.stage(m2)
    out = []
    coord.drain(bus) { |m| out << m.meta[:session_id] }
    expect(out.first).to eq("floor")
  end
end

