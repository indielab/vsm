# frozen_string_literal: true
module VSM
  module MCP
    class RemoteToolCapsule < VSM::ToolCapsule
      attr_writer :bus

      def initialize(client:, remote_name:, descriptor:)
        @client = client
        @remote_name = remote_name
        @descriptor = descriptor # { name:, description:, input_schema: }
      end

      def tool_descriptor
        VSM::Tool::Descriptor.new(
          name:        @descriptor[:name],
          description: @descriptor[:description],
          schema:      @descriptor[:input_schema]
        )
      end

      def execution_mode
        :thread
      end

      def run(args)
        @bus&.emit VSM::Message.new(kind: :progress, payload: "mcp call #{@client.name}.#{@remote_name}", path: [:mcp, :client, @client.name, @remote_name])
        out = @client.call_tool(name: @remote_name, arguments: args || {})
        @bus&.emit VSM::Message.new(kind: :progress, payload: "mcp result #{@client.name}.#{@remote_name}", path: [:mcp, :client, @client.name, @remote_name])
        out.to_s
      rescue => e
        "ERROR: #{e.class}: #{e.message}"
      end
    end
  end
end
