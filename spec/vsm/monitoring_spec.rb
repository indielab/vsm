# frozen_string_literal: true
require "spec_helper"
require "tmpdir"

RSpec.describe VSM::Monitoring do
  include Async::RSpec::Reactor

  it "writes a JSONL event per message" do
    Dir.mktmpdir do |dir|
      stub_const("VSM::Monitoring::LOG", File.join(dir, "vsm.log.jsonl"))
      mon = described_class.new
      bus = VSM::AsyncChannel.new
      mon.observe(bus)

      bus.emit VSM::Message.new(kind: :user, payload: "hi", meta: { session_id: "s" })
      Async { |t| t.sleep 0.05 }

      data = File.read(VSM::Monitoring::LOG)
      expect(data).to include("\"kind\":\"user\"")
      expect(data).to include("\"session_id\":\"s\"")
    end
  end
end

