# frozen_string_literal: true
require "async"
module VSM
  class Capsule
    attr_reader :name, :bus, :homeostat, :roles, :children

    def initialize(name:, roles:, children: {})
      @name     = name.to_sym
      @roles    = roles
      @children = children
      ctx = { operations_children: children.transform_keys(&:to_s) }
      @bus = AsyncChannel.new(context: ctx)
      @homeostat = Homeostat.new
      # Inject bus into children that accept it, to enable richer observability
      @children.each_value { |c| c.bus = @bus if c.respond_to?(:bus=) }
      wire_observers!
    end

    def run
      Async do
        loop do
          message = @bus.pop
          roles[:coordination].stage(message)
          roles[:coordination].drain(@bus) { |m| dispatch(m) }
        end
      end
    end

    def dispatch(message)
      return roles[:identity].alert(message) if homeostat.alarm?(message)
      roles[:governance].enforce(message) { route(_1) }
    end

    def route(message)
      roles[:operations].handle(message, bus: @bus, children: @children) ||
      roles[:intelligence].handle(message, bus: @bus) ||
      roles[:identity].handle(message, bus: @bus)
    end

    private

    def wire_observers!
      roles.values.each { |r| r.respond_to?(:observe) && r.observe(@bus) }
    end
  end
end
