# frozen_string_literal: true
module VSM
  class Identity
    def initialize(identity:, invariants: [])
      @identity, @invariants = identity, invariants
    end
    def observe(bus); end
    def handle(message, bus:, **) = false
    def alert(message); end
  end
end
