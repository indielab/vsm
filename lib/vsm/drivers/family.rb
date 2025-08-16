# frozen_string_literal: true
module VSM
  module Drivers
    module Family
      def self.of(driver)
        case driver
        when VSM::Drivers::OpenAI::AsyncDriver    then :openai
        when VSM::Drivers::Anthropic::AsyncDriver then :anthropic
        when VSM::Drivers::Gemini::AsyncDriver    then :gemini
        else :openai
        end
      end
    end
  end
end

