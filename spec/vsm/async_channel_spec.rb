# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::AsyncChannel do
  include Async::RSpec::Reactor

  it "broadcasts to subscribers and supports pop" do
    chan = described_class.new(context: { foo: "bar" })
    seen = []
    chan.subscribe { |m| seen << m.kind }

    m1 = VSM::Message.new(kind: :user, payload: "hi")
    m2 = VSM::Message.new(kind: :assistant, payload: "yo")

    chan.emit(m1)
    chan.emit(m2)

    # pop returns them in order
    expect(chan.pop).to eq(m1)
    expect(chan.pop).to eq(m2)

    # fan-out happened (in async tasks)
    Async { |task| task.sleep 0.05 } # allow fan-out tasks to run
    expect(seen).to include(:user, :assistant)
    expect(chan.context[:foo]).to eq("bar")
  end
end

