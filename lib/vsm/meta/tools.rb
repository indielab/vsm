# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "pathname"

require_relative "snapshot_builder"
require_relative "snapshot_cache"

module VSM
  module Meta
    module Tools
      class Base < VSM::ToolCapsule
        attr_reader :root, :snapshot_cache, :draft_store

        def initialize(root:, snapshot_cache:, draft_store: nil)
          @root = root
          @snapshot_cache = snapshot_cache
          @draft_store = draft_store
        end

        def execution_mode = :fiber

        private

        def snapshot
          snapshot_cache.fetch[:data]
        end

        def roles_summary(roles_hash)
          return {} unless roles_hash

          roles_hash.transform_values do |info|
            {
              class: info[:class],
              constructor_args: info[:constructor_args]
            }
          end
        end

        def flatten_tools(node, acc)
          ops = node.dig(:operations, :children) || {}
          ops.each_value do |child|
            case child[:kind]
            when "tool"
              acc << child
            when "capsule"
              acc << child if child[:tool]
              flatten_tools(child, acc)
            end
          end
          acc
        end

        def tool_index
          flatten_tools(snapshot, []).each_with_object({}) do |entry, acc|
            key = entry.dig(:tool, :name) || entry[:name]
            acc[key] = entry
            acc[entry[:path].join("/")] = entry
          end
        end

        def read_source(path, start_line, window: 120)
          return nil if path.nil?
          full = File.expand_path(path, Dir.pwd)
          return nil unless File.file?(full)

          lines = File.readlines(full, chomp: true)
          slice = lines[[start_line - 1, 0].max, window] || []
          slice.join("\n")
        rescue StandardError => e
          "ERROR reading source: #{e.class}: #{e.message}"
        end

        def emit_audit(payload, path: [:meta, tool_descriptor.name], meta: {})
          root.bus.emit(
            VSM::Message.new(
              kind: :audit,
              payload: payload,
              path: path,
              meta: meta.merge(tool: tool_descriptor.name)
            )
          )
        end

        def workspace_root
          @workspace_root ||= File.expand_path(".", Dir.pwd)
        end

        def ensure_within_workspace!(path)
          absolute = File.expand_path(path, Dir.pwd)
          unless absolute.start_with?(workspace_root)
            raise "path escapes workspace: #{path}"
          end
          absolute
        end

        def relative_to_workspace(path)
          Pathname.new(path).relative_path_from(Pathname.new(workspace_root)).to_s
        rescue ArgumentError
          path
        end

        def draft_store!
          draft_store || (raise "draft store not configured")
        end
      end

      class SummarizeSelf < Base
        tool_name "meta_summarize_self"
        tool_description "Summarize the current capsule including roles and tools"
        tool_schema({ type: "object", properties: {}, additionalProperties: false })

        def run(_args)
          data = snapshot
          tools = flatten_tools(data, []).select { _1[:kind] == "tool" }
          {
            capsule: {
              name: data[:name],
              path: data[:path],
              class: data[:class],
              roles: roles_summary(data[:roles])
            },
            stats: {
              total_tools: tools.size,
              tool_names: tools.map { _1.dig(:tool, :name) }
            },
            snapshot: data
          }
        end
      end

      class ListTools < Base
        tool_name "meta_list_tools"
        tool_description "List all tools available in the current organism"
        tool_schema({ type: "object", properties: {}, additionalProperties: false })

        def run(_args)
          tools = flatten_tools(snapshot, []).select { _1[:kind] == "tool" }
          {
            tools: tools.map do |entry|
              descriptor = entry[:tool] || {}
              {
                tool_name: descriptor[:name] || entry[:name],
                capsule_path: entry[:path],
                description: descriptor[:description],
                schema: descriptor[:schema],
                class: entry[:class]
              }
            end
          }
        end
      end

      class ExplainTool < Base
        tool_name "meta_explain_tool"
        tool_description "Provide code and context for a specific tool"
        tool_schema({
          type: "object",
          properties: {
            tool: {
              type: "string",
              description: "Tool name or capsule path (e.g. meta/meta_explain_tool)"
            }
          },
          required: ["tool"],
          additionalProperties: false
        })

        def run(args)
          target = args["tool"].to_s.strip
          raise "tool name required" if target.empty?

          entry = tool_index[target]
          raise "unknown tool: #{target}" unless entry

          descriptor = entry[:tool] || {}
          run_source = source_for(entry, "run")

          {
            tool: {
              name: descriptor[:name] || entry[:name],
              capsule_path: entry[:path],
              class: entry[:class],
              description: descriptor[:description],
              schema: descriptor[:schema]
            },
            code: run_source,
            source_locations: entry[:source_locations],
            parent_roles: roles_summary(snapshot[:roles])
          }
        end

        private

        def source_for(entry, method_name)
          location = entry[:source_locations]&.find { _1[:method] == method_name } || entry[:source_locations]&.first
          return nil unless location

          {
            path: location[:path],
            start_line: location[:line],
            method: location[:method],
            snippet: read_source(location[:path], location[:line])
          }
        end
      end

      # Write-path tools removed: keeping read-only meta tools only.
    end
  end
end
