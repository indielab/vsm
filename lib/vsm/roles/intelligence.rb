# frozen_string_literal: true
module VSM
  class Intelligence
    def observe(bus); end
    def handle(message, bus:, **)
      false # app supplies its own subclass that talks to an LLM driver
    end
  end
end
