# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::Homeostat do
  it "flags algedonic messages" do
    h = described_class.new
    m = VSM::Message.new(kind: :user, payload: "x", meta: { severity: :algedonic })
    expect(h.alarm?(m)).to be true
    expect(h.alarm?(VSM::Message.new(kind: :user, payload: "x"))).to be false
  end
end

