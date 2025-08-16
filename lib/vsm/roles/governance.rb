# frozen_string_literal: true
module VSM
  class Governance
    def observe(bus); end
    def enforce(message)
      yield message
    end
  end
end
