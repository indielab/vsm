# frozen_string_literal: true
module VSM
  class Port
    def initialize(capsule:) = (@capsule = capsule)
    def ingress(_event) = raise NotImplementedError
    def egress_subscribe = @capsule.bus.subscribe { |m| render_out(m) }
    def render_out(_message) = nil
  end
end

