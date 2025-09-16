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

        def flatten_capsules(node, acc)
          # node is a capsule-like hash per SnapshotBuilder
          acc << node if node.is_a?(Hash) && node[:kind] == "capsule"
          children = node.dig(:operations, :children) || {}
          children.each_value do |child|
            next unless child[:kind] == "capsule"
            flatten_capsules(child, acc)
          end
          acc
        end

        def capsules_index
          flatten_capsules(snapshot, []).each_with_object({}) do |entry, acc|
            path_key = entry[:path].join("/")
            acc[path_key] = entry
            # Also index by leaf name for convenience (non-unique, last wins)
            acc[entry[:name]] = entry
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

      class ExplainRole < Base
        tool_name "meta_explain_role"
        tool_description "Explain a VSM role implementation with code context"
        tool_schema({
          type: "object",
          properties: {
            role: {
              type: "string",
              description: "Role name (identity, governance, coordination, intelligence, monitoring, operations)"
            },
            capsule: {
              type: "string",
              description: "Optional capsule path or name (e.g. meta or parent/child). Defaults to root capsule"
            }
          },
          required: ["role"],
          additionalProperties: false
        })

        ROLE_SUMMARIES = {
          "identity" => "Defines purpose and invariants; handles alerts/escalation and represents the capsule’s identity.",
          "governance" => "Applies policy and safety constraints; enforces budgets/limits around message handling.",
          "coordination" => "Stages, orders, and drains messages; manages session floor/turn-taking across events.",
          "intelligence" => "Plans and converses using an LLM; maintains conversation state and invokes tools.",
          "operations" => "Executes tool calls by routing to child tool capsules with appropriate execution mode.",
          "monitoring" => "Observes the bus and records telemetry/metrics for observability and debugging."
        }.freeze

        def run(args)
          role_name = args["role"].to_s.strip
          raise "role name required" if role_name.empty?

          target_capsule = resolve_capsule(args["capsule"]) || snapshot
          live_capsule = resolve_live_capsule(target_capsule)
          role_instance = resolve_role_instance(role_name, live_capsule)
          roles = target_capsule[:roles] || {}
          role_info = roles[role_name]
          raise "unknown role: #{role_name}" unless role_info

          {
            capsule: {
              name: target_capsule[:name],
              path: target_capsule[:path],
              class: target_capsule[:class]
            },
            role: {
              name: role_name,
              class: role_info[:class],
              constructor_args: role_info[:constructor_args]
            },
            vsm_summary: ROLE_SUMMARIES[role_name] || "",
            source_locations: role_info[:source_locations],
            code: source_blocks_for(role_info[:source_locations]),
            sibling_roles: roles_summary(roles),
            role_specific: role_specific_details(role_name, target_capsule, live_capsule, role_instance)
          }
        end

        private

        def resolve_capsule(capsule_arg)
          return nil if capsule_arg.nil? || capsule_arg.to_s.strip.empty?
          idx = capsules_index
          idx[capsule_arg.to_s] || idx[capsule_arg.to_s.split("/").join("/")]
        end

        def source_blocks_for(locs)
          Array(locs).filter_map do |loc|
            next unless loc && loc[:path]
            {
              path: loc[:path],
              start_line: loc[:line],
              method: loc[:method],
              snippet: read_source(loc[:path], loc[:line])
            }
          end
        end

        def role_specific_details(role_name, capsule_entry, live_capsule, role_instance)
          case role_name
          when "operations"
            ops_children = operations_children_for(capsule_entry)
            augmented = augment_children_with_live_data(live_capsule, ops_children)
            { children: augmented }
          when "intelligence"
            ops_children = operations_children_for(capsule_entry)
            tools = ops_children.select { |c| c[:kind] == "tool" }
            {
              driver_class: safe_class_name(role_instance&.driver),
              system_prompt_present: !!(role_instance && safe_iv_get(role_instance, :@system_prompt)),
              sessions_open: safe_sessions_size(role_instance),
              available_tools: tools.map { |c| { tool_name: c[:tool_name], capsule_path: c[:capsule_path], class: c[:class] } }
            }
          when "monitoring"
            { log_path_constant: monitoring_log_constant_for(capsule_entry) }
              .merge(monitoring_file_stats(capsule_entry))
              .compact
          when "coordination"
            {
              supports_floor_control: role_instance.respond_to?(:grant_floor!) && role_instance.respond_to?(:wait_for_turn_end),
              queue_size: safe_iv_size(role_instance, :@queue),
              turn_waiters: safe_iv_size(role_instance, :@turn_waiters),
              current_floor_session: safe_iv_get(role_instance, :@floor_by_session),
              ordering_rank: sample_ordering_rank(role_instance)
            }
          when "identity"
            {
              identity: safe_iv_get(role_instance, :@identity),
              invariants: safe_iv_get(role_instance, :@invariants) || [],
              alerts_supported: role_instance.respond_to?(:alert)
            }
          when "governance"
            ops_children = operations_children_for(capsule_entry)
            augmented = augment_children_with_live_data(live_capsule, ops_children)
            injected_into = augmented.select { |c| c[:accepts_governance] }.map { |c| c[:name] }
            {
              injected_into_children: injected_into,
              observes_bus: role_instance.respond_to?(:observe),
              wraps_enforce: role_instance.respond_to?(:enforce)
            }
          else
            {}
          end
        end

        def operations_children_for(capsule_entry)
          ops = capsule_entry.dig(:operations, :children) || {}
          ops.values.filter_map do |child|
            next unless child # safety
            descriptor = child[:tool] || {}
            {
              name: child[:name],
              kind: child[:kind],
              class: child[:class],
              capsule_path: child[:path],
              tool_name: descriptor[:name] || child[:name],
              description: descriptor[:description],
              schema: descriptor[:schema]
            }
          end
        end

        def augment_children_with_live_data(live_capsule, children_list)
          children_list.map do |info|
            child = live_child_from_path(info[:capsule_path]) || live_capsule&.children&.[](info[:name])
            extra = {}
            if child
              if child.respond_to?(:execution_mode)
                extra[:execution_mode] = child.execution_mode
              end
              extra[:accepts_governance] = child.respond_to?(:governance=)
              if child.respond_to?(:tool_descriptor)
                # confirm real descriptor name if available
                begin
                  extra[:tool_name] = child.tool_descriptor.name
                rescue StandardError
                end
              end
            end
            info.merge(extra)
          end
        end

        def monitoring_file_stats(capsule_entry)
          path = monitoring_log_constant_for(capsule_entry)
          return {} unless path
          begin
            abs = ensure_within_workspace?(path)
            exists = File.file?(abs)
            size = exists ? File.size(abs) : 0
            { log_exists: exists, log_size_bytes: size, log_relative_path: relative_to_workspace(abs) }
          rescue StandardError
            {}
          end
        end

        def monitoring_log_constant_for(capsule_entry)
          # Best effort: if class constant is VSM::Monitoring and defines LOG, surface it
          klass_name = capsule_entry.dig(:roles, "monitoring", :class)
          return nil unless klass_name
          begin
            klass = resolve_constant(klass_name)
            return klass::LOG if klass && klass.const_defined?(:LOG)
          rescue NameError
          end
          nil
        end

        def resolve_constant(name)
          name.split("::").reject(&:empty?).inject(Object) { |ns, part| ns.const_get(part) }
        end

        def resolve_live_capsule(capsule_entry)
          path = capsule_entry[:path] || []
          cur = root
          # skip the first element which is the root name
          path.drop(1).each do |name|
            cur = cur.children[name.to_s]
            break unless cur
          end
          cur.is_a?(VSM::Capsule) ? cur : root
        rescue StandardError
          root
        end

        def live_child_from_path(path)
          return nil unless path && !path.empty?
          cur = root
          path.drop(1).each_with_index do |name, idx|
            child = cur.children[name.to_s] rescue nil
            return child if child.nil? || idx == path.size - 2 # last hop returns child
            # If child is a capsule, descend into its children
            if child.respond_to?(:children)
              cur = child
            else
              return child
            end
          end
        rescue StandardError
          nil
        end

        def resolve_role_instance(role_name, live_capsule)
          sym = role_name.to_sym rescue role_name
          live_capsule&.roles&.[](sym)
        end

        def safe_class_name(obj)
          obj&.class&.name
        end

        def safe_sessions_size(role_instance)
          return nil unless role_instance
          st = role_instance.instance_variable_get(:@sessions) rescue nil
          st.respond_to?(:size) ? st.size : nil
        end

        def safe_iv_size(obj, ivar)
          return nil unless obj
          val = obj.instance_variable_get(ivar) rescue nil
          if val.respond_to?(:size)
            val.size
          elsif val.respond_to?(:length)
            val.length
          else
            nil
          end
        end

        def safe_iv_get(obj, ivar)
          obj&.instance_variable_get(ivar) rescue nil
        end

        def sample_ordering_rank(role_instance)
          return nil unless role_instance && role_instance.respond_to?(:order)
          kinds = %i[user tool_result plan assistant_delta assistant]
          kinds.each_with_object({}) do |k, acc|
            msg = VSM::Message.new(kind: k, payload: nil)
            acc[k] = role_instance.order(msg)
          end
        rescue StandardError
          nil
        end
      end

      # Write-path tools removed: keeping read-only meta tools only.
    end
  end
end
