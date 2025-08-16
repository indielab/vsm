# frozen_string_literal: true
require "spec_helper"

RSpec.describe "Executors" do
  it "FiberExecutor runs run() inline" do
    tool = FakeEchoTool.new
    expect(VSM::Executors::FiberExecutor.call(tool, { "text" => "hi" })).to eq("echo: hi")
  end

  it "ThreadExecutor runs code on a separate thread and returns result" do
    tool = SlowTool.new
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = VSM::Executors::ThreadExecutor.call(tool, { "id" => 7 })
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(result).to eq("slow-7")
    expect(t1 - t0).to be >= 0.25
  end

  it "ThreadExecutor surfaces exceptions" do
    tool = ErrorTool.new
    expect { VSM::Executors::ThreadExecutor.call(tool, {}) }.to raise_error(RuntimeError, /kapow/)
  end
end

