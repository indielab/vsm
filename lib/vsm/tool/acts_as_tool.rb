# frozen_string_literal: true
module VSM
  module ActsAsTool
    def self.included(base) = base.extend(ClassMethods)

    module ClassMethods
      def tool_name(value = nil);  @tool_name = value if value; @tool_name; end
      def tool_description(value = nil); @tool_description = value if value; @tool_description; end
      def tool_schema(value = nil); @tool_schema = value if value; @tool_schema; end
    end

    def tool_descriptor
      VSM::Tool::Descriptor.new(
        name: self.class.tool_name,
        description: self.class.tool_description,
        schema: self.class.tool_schema
      )
    end
  end
end
