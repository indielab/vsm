# frozen_string_literal: true
require_relative "dsl"
require_relative "mcp/client"
require_relative "mcp/remote_tool_capsule"

module VSM
  module DSL
    class Builder
      class ChildrenBuilder
        # Reflect tools from a remote MCP server and add them as tool capsules.
        # Options:
        #   include: Array<String> whitelist of tool names
        #   exclude: Array<String> blacklist of tool names
        #   prefix:  String prefix for local names to avoid collisions
        #   env:     Hash environment passed to the server process
        #   cwd:     Working directory for spawning the process
        #
        # Example:
        #   mcp_server :smith, cmd: "smith-server --stdio", include: %w[search read], prefix: "smith_"
        def mcp_server(name, cmd:, env: {}, include: nil, exclude: nil, prefix: nil, cwd: nil)
          client = VSM::MCP::Client.new(cmd: cmd, env: env, cwd: cwd, name: name.to_s).start
          tools  = client.list_tools
          tools.each do |t|
            tool_name = t[:name]
            next if include && !Array(include).include?(tool_name)
            next if exclude &&  Array(exclude).include?(tool_name)
            local_name = [prefix, tool_name].compact.join
            capsule = VSM::MCP::RemoteToolCapsule.new(client: client, remote_name: tool_name, descriptor: t)
            @children[local_name] = capsule
          end
        end
      end
    end
  end
end

