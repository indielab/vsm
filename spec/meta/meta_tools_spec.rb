# frozen_string_literal: true

require "spec_helper"

RSpec.describe "VSM meta read-only tools" do
  class MetaSpecTool < VSM::ToolCapsule
    tool_name "meta_spec_tool"
    tool_description "Spec helper tool"
    tool_schema({ type: "object", properties: {}, additionalProperties: false })

    def run(_args)
      "ok"
    end
  end

  let(:host) do
    VSM::DSL.define(:meta_spec_host) do
      identity     klass: VSM::Identity,     args: { identity: "meta_spec_host", invariants: [] }
      governance   klass: VSM::Governance,   args: {}
      coordination klass: VSM::Coordination, args: {}
      intelligence klass: VSM::Intelligence, args: {}
      monitoring   klass: VSM::Monitoring,   args: {}
      operations do
        meta_tools
        capsule :meta_spec_tool, klass: MetaSpecTool
      end
    end
  end

  it "registers meta tools on the host capsule" do
    expect(host.children.keys).to include("meta_summarize_self", "meta_list_tools", "meta_explain_tool")
  end

  it "list tools returns descriptors" do
    list_tool = host.children.fetch("meta_list_tools")
    result = list_tool.run({})
    names = result[:tools].map { _1[:tool_name] }
    expect(names).to include("meta_spec_tool")
  end

  it "explain tool returns source snippet" do
    explain = host.children.fetch("meta_explain_tool")
    result = explain.run({ "tool" => "meta_spec_tool" })
    expect(result[:tool][:name]).to eq("meta_spec_tool")
    expect(result[:code][:snippet]).to include("def run")
  end

  it "explains a role and returns code snippets" do
    explain_role = host.children.fetch("meta_explain_role")
    result = explain_role.run({ "role" => "coordination" })
    expect(result[:role][:name]).to eq("coordination")
    expect(result[:role][:class]).to include("VSM::Coordination")
    expect(result[:code]).to be_an(Array)
    expect(result[:code]).not_to be_empty
    expect(result[:code].first[:snippet]).to include("def ")
    expect(result[:vsm_summary].to_s.length).to be > 0
  end

  it "explains operations with child tools context" do
    explain_role = host.children.fetch("meta_explain_role")
    result = explain_role.run({ "role" => "operations" })
    expect(result[:role][:name]).to eq("operations")
    children = result.dig(:role_specific, :children)
    expect(children).to be_an(Array)
    names = children.map { _1[:tool_name] }
    expect(names).to include("meta_spec_tool")
  end

  it "summarize self includes stats" do
    summarize = host.children.fetch("meta_summarize_self")
    result = summarize.run({})
    expect(result[:stats][:total_tools]).to be >= 1
    expect(result[:capsule][:name]).to eq("meta_spec_host")
  end
end

RSpec.describe "meta tools prefix option" do
  it "registers tools with a prefix" do
    cap = VSM::DSL.define(:meta_prefixed) do
      identity     klass: VSM::Identity,     args: { identity: "meta_prefixed", invariants: [] }
      governance   klass: VSM::Governance,   args: {}
      coordination klass: VSM::Coordination, args: {}
      intelligence klass: VSM::Intelligence, args: {}
      operations do
        meta_tools prefix: "inspector_"
      end
    end

    expect(cap.children.keys).to include("inspector_meta_summarize_self")
  end
end

RSpec.describe "meta tools selection" do
  it "allows selecting subset via only" do
    cap = VSM::DSL.define(:meta_only) do
      identity     klass: VSM::Identity,     args: { identity: "meta_only", invariants: [] }
      governance   klass: VSM::Governance,   args: {}
      coordination klass: VSM::Coordination, args: {}
      intelligence klass: VSM::Intelligence, args: {}
      operations do
        meta_tools only: [:meta_list_tools]
      end
    end

    expect(cap.children.keys).to include("meta_list_tools")
    expect(cap.children.keys).not_to include("meta_summarize_self")
  end

  it "allows excluding tools" do
    cap = VSM::DSL.define(:meta_except) do
      identity     klass: VSM::Identity,     args: { identity: "meta_except", invariants: [] }
      governance   klass: VSM::Governance,   args: {}
      coordination klass: VSM::Coordination, args: {}
      intelligence klass: VSM::Intelligence, args: {}
      operations do
        meta_tools except: [:meta_explain_tool]
      end
    end

    expect(cap.children.keys).to include("meta_list_tools")
    expect(cap.children.keys).not_to include("meta_explain_tool")
  end
end
