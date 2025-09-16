# frozen_string_literal: true

require "pathname"

require_relative "support"

module VSM
  module Meta
    class SnapshotBuilder
      ROLE_METHOD_HINTS = {
        identity: %i[handle alert observe initialize],
        governance: %i[enforce observe initialize],
        coordination: %i[stage drain order grant_floor! wait_for_turn_end initialize],
        operations: %i[handle observe initialize],
        intelligence: %i[handle system_prompt offer_tools? initialize],
        monitoring: %i[observe handle initialize]
      }.freeze

      def initialize(root:)
        @root = root
      end

      def call
        snapshot_capsule(@root, path: [@root.name.to_s])
      end

      private

      def snapshot_capsule(capsule, path:)
        {
          kind: "capsule",
          name: capsule.name.to_s,
          class: capsule.class.name,
          path: path.dup,
          roles: snapshot_roles(capsule.roles),
          operations: snapshot_operations(capsule.children, path: path),
          meta: {}
        }
      end

      def snapshot_roles(roles)
        roles.each_with_object({}) do |(role_name, role_instance), acc|
          acc[role_name.to_s] = snapshot_role(role_name, role_instance)
        end
      end

      def snapshot_role(role_name, role_instance)
        {
          class: role_instance.class.name,
          constructor_args: Support.fetch_constructor_args(role_instance),
          source_locations: method_locations(role_instance.class, ROLE_METHOD_HINTS[role_name] || %i[initialize]),
          summary: nil
        }
      end

      def snapshot_operations(children, path:)
        return { children: {} } if children.nil? || children.empty?

        ops = {}
        children.each do |name, child|
          ops[name.to_s] = snapshot_child(child, path: path + [name.to_s])
        end
        { children: ops }
      end

      def snapshot_child(child, path:)
        base = {
          name: path.last,
          class: child.class.name,
          path: path,
          constructor_args: Support.fetch_constructor_args(child),
          source_locations: [],
          roles: nil,
          operations: nil
        }

        if child.respond_to?(:roles) && child.respond_to?(:children)
          base[:kind] = "capsule"
          base[:roles] = snapshot_roles(child.roles)
          base[:operations] = snapshot_operations(child.children || {}, path: path)
          base[:source_locations] = method_locations(child.class, %i[initialize])
        elsif child.respond_to?(:tool_descriptor)
          base[:kind] = "tool"
          descriptor = child.tool_descriptor
          base[:tool] = {
            name: descriptor.name,
            description: descriptor.description,
            schema: descriptor.schema
          }
          base[:source_locations] = method_locations(child.class, %i[run execution_mode initialize])
        else
          base[:kind] = "object"
          base[:source_locations] = method_locations(child.class, %i[initialize])
        end

        base
      end

      def method_locations(klass, candidates)
        candidates.filter_map do |meth|
          next unless klass.instance_methods.include?(meth)
          location = klass.instance_method(meth).source_location
          next if location.nil?
          { method: meth.to_s, path: relative_path(location[0]), line: location[1] }
        rescue NameError
          nil
        end
      end

      def relative_path(path)
        return path if path.nil?
        root = Pathname.new(Dir.pwd)
        begin
          Pathname.new(path).relative_path_from(root).to_s
        rescue ArgumentError
          path
        end
      end
    end
  end
end
