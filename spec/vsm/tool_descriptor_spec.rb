# frozen_string_literal: true
require "spec_helper"

RSpec.describe VSM::Tool::Descriptor do
  let(:schema) { { "type" => "object", "properties" => { "x" => { "type" => "string" } }, "required" => ["x"] } }
  subject(:desc) { described_class.new(name: "t", description: "d", schema:) }

  it "converts to OpenAI tool" do
    t = desc.to_openai_tool
    expect(t[:type]).to eq("function")
    expect(t[:function][:name]).to eq("t")
    expect(t[:function][:parameters]).to eq(schema)
  end

  it "converts to Anthropic tool" do
    t = desc.to_anthropic_tool
    expect(t[:name]).to eq("t")
    expect(t[:input_schema]).to eq(schema)
  end

  it "converts to Gemini function declaration" do
    t = desc.to_gemini_tool
    expect(t[:name]).to eq("t")
    expect(t[:parameters]).to eq(schema)
  end
end

