# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::ActsAsTool do
  it "provides descriptor from class macros" do
    klass = Class.new(VSM::ToolCapsule) do
      tool_name "alpha"
      tool_description "desc"
      tool_schema({ type: "object", properties: {}, required: [] })
      def run(_) = "ok"
    end

    d = klass.new.tool_descriptor
    expect(d.name).to eq("alpha")
    expect(d.description).to eq("desc")
    expect(d.schema).to include(type: "object")
  end
end

