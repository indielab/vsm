# frozen_string_literal: true

require_relative "meta/support"
require_relative "meta/snapshot_builder"
require_relative "meta/snapshot_cache"
require_relative "meta/tools"

module VSM
  module Meta
    DEFAULT_TOOL_MAP = {
      "meta_summarize_self" => Tools::SummarizeSelf,
      "meta_list_tools" => Tools::ListTools,
      "meta_explain_tool" => Tools::ExplainTool
    }.freeze

    module_function

    def attach!(capsule, prefix: "", only: nil, except: nil)
      cache = SnapshotCache.new(SnapshotBuilder.new(root: capsule))
      installed = {}

      tool_map = select_tools(only:, except:).transform_keys { |name| "#{prefix}#{name}" }
      tool_map.each do |tool_name, klass|
        tool = klass.new(root: capsule, snapshot_cache: cache)
        if capsule.roles[:governance] && tool.respond_to?(:governance=)
          tool.governance = capsule.roles[:governance]
        end
        register_tool(capsule, tool_name, tool)
        installed[tool_name] = tool
      end

      cache.fetch
      installed
    end

    def select_tools(only:, except:)
      map = DEFAULT_TOOL_MAP
      if only && !Array(only).empty?
        keys = Array(only).map(&:to_s)
        map = map.select { |name, _| keys.include?(name) }
      end
      if except && !Array(except).empty?
        rejects = Array(except).map(&:to_s)
        map = map.reject { |name, _| rejects.include?(name) }
      end
      map
    end

    def register_tool(capsule, name, tool)
      key = name.to_s
      capsule.children[key] = tool
      context_children = capsule.bus.context[:operations_children]
      if context_children.is_a?(Hash)
        context_children[key] = tool
      end
    end
  end
end
