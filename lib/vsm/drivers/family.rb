# frozen_string_literal: true
module VSM
  module Drivers
    module Family
      def self.of(driver)
        case driver
        when VSM::Drivers::OpenAI::DriverAsync   then :openai
        when VSM::Drivers::Anthropic::DriverAsync then :anthropic
        when VSM::Drivers::Gemini::DriverAsync    then :gemini
        else :openai
        end
      end
    end
  end
end

