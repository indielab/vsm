# frozen_string_literal: true
require "json"
require "async"

module VSM
  module Ports
    module MCP
      # Exposes the capsule's tools as an MCP server over stdio (NDJSON JSON-RPC).
      # Implemented methods: tools/list, tools/call.
      class ServerStdio < VSM::Port
        def initialize(capsule:)
          super(capsule: capsule)
          @waiters = {}
          @waiters_mutex = Mutex.new
        end

        def egress_subscribe
          # Single subscriber that resolves tool_result waiters by corr_id
          @capsule.bus.subscribe do |m|
            next unless m.kind == :tool_result
            q = nil
            @waiters_mutex.synchronize { q = @waiters.delete(m.corr_id.to_s) }
            q&.enqueue(m)
          end
          super
        end

        def loop
          $stdout.sync = true
          while (line = $stdin.gets)
            begin
              req = JSON.parse(line)
            rescue => e
              write_err(nil, code: -32700, message: "Parse error: #{e.message}")
              next
            end

            id = req["id"]
            method = req["method"]
            params = req["params"] || {}
            case method
            when "tools/list"
              write_ok(id, { tools: list_tools })
            when "tools/call"
              name = params["name"].to_s
              args = params["arguments"] || {}
              res = call_local_tool(id, name, args)
              write_ok(id, { content: [{ type: "text", text: res.to_s }] })
            else
              write_err(id, code: -32601, message: "Method not found: #{method}")
            end
          end
        end

        private

        def list_tools
          ops = @capsule.bus.context[:operations_children] || {}
          ops.values
             .select { _1.respond_to?(:tool_descriptor) }
             .map { to_mcp_descriptor(_1.tool_descriptor) }
        end

        def to_mcp_descriptor(desc)
          {
            "name" => desc.name,
            "description" => desc.description,
            "input_schema" => desc.schema
          }
        end

        def call_local_tool(req_id, name, args)
          corr = req_id.to_s
          q = Async::Queue.new
          @waiters_mutex.synchronize { @waiters[corr] = q }
          @capsule.bus.emit VSM::Message.new(
            kind: :tool_call,
            payload: { tool: name, args: args },
            corr_id: corr,
            meta: { session_id: "mcp:stdio" },
            path: [:mcp, :server, name]
          )
          msg = q.dequeue
          msg.payload
        ensure
          @waiters_mutex.synchronize { @waiters.delete(corr) }
        end

        def write_ok(id, result)
          puts JSON.dump({ jsonrpc: "2.0", id: id, result: result })
          $stdout.flush
        end

        def write_err(id, code:, message:)
          puts JSON.dump({ jsonrpc: "2.0", id: id, error: { code: code, message: message } })
          $stdout.flush
        end
      end
    end
  end
end
