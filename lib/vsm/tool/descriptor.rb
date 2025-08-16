# frozen_string_literal: true
module VSM
  module Tool
    Descriptor = Struct.new(:name, :description, :schema, keyword_init: true) do
      def to_openai_tool
        { type: "function", function: { name:, description:, parameters: schema } }
      end
      def to_anthropic_tool
        { name:, description:, input_schema: schema }
      end
      def to_gemini_tool
        { name:, description:, parameters: schema }
      end
    end
  end
end
