# frozen_string_literal: true
module VSM
  class Homeostat
    def initialize
      @limits = { tokens: 8_000, time_ms: 15_000, bytes: 2_000_000 }
      @usage  = Hash.new(0)
    end

    def alarm?(message)
      message.meta&.dig(:severity) == :algedonic
    end
  end
end
