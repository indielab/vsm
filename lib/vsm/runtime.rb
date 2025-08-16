# frozen_string_literal: true
require "async"

module VSM
  module Runtime
    def self.start(capsule, ports: [])
      Async do |task|
        capsule.run
        ports.each do |p|
          p.egress_subscribe if p.respond_to?(:egress_subscribe)
          task.async { p.loop } if p.respond_to?(:loop)
        end
        task.sleep
      end
    end
  end
end

