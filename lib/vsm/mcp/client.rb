# frozen_string_literal: true
require "open3"
require "shellwords"
require_relative "jsonrpc"

module VSM
  module MCP
    class Client
      attr_reader :name

      def initialize(cmd:, env: {}, cwd: nil, name: nil)
        @cmd, @env, @cwd, @name = cmd, env, cwd, (name || cmd.split.first)
        @stdin = @stdout = @stderr = @wait_thr = nil
        @rpc = nil
        @stderr_thread = nil
      end

      def start
        opts = {}
        opts[:chdir] = @cwd if @cwd
        args = @cmd.is_a?(Array) ? @cmd : Shellwords.split(@cmd.to_s)
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@env || {}, *args, **opts)
        # Drain stderr to avoid blocking if the server writes logs
        @stderr_thread = Thread.new do
          begin
            @stderr.each_line { |_line| }
          rescue StandardError
          end
        end
        @rpc = JSONRPC::Stdio.new(r: @stdout, w: @stdin)
        self
      end

      def stop
        begin
          @stdin&.close
        rescue StandardError
        end
        begin
          @stdout&.close
        rescue StandardError
        end
        begin
          @stderr&.close
        rescue StandardError
        end
        begin
          @stderr_thread&.kill
        rescue StandardError
        end
        begin
          @wait_thr&.kill
        rescue StandardError
        end
        nil
      end

      # Returns Array<Hash> with symbol keys: :name, :description, :input_schema
      def list_tools
        raw = @rpc.request("tools/list")
        arr = (raw && raw["tools"]) || []
        arr.map do |t|
          {
            name: t["name"].to_s,
            description: t["description"].to_s,
            input_schema: (t["input_schema"] || {})
          }
        end
      end

      # Returns a String (first text content) or a JSON string fallback
      def call_tool(name:, arguments: {})
        res = @rpc.request("tools/call", { "name" => name, "arguments" => arguments })
        content = Array(res["content"])
        item = content.find { |c| c["type"] == "text" } || content.first
        item ? (item["text"] || item.to_s) : res.to_s
      end
    end
  end
end
