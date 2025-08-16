# frozen_string_literal: true
module VSM
  module DSL
    class Builder
      def initialize(name)
        @name = name
        @roles = {}
        @children = {}
      end

      def identity(klass: VSM::Identity, args: {})     = (@roles[:identity]     = klass.new(**args))
      def governance(klass: VSM::Governance, args: {}) = (@roles[:governance]   = klass.new(**args))
      def coordination(klass: VSM::Coordination, args: {}) = (@roles[:coordination] = klass.new(**args))
      def intelligence(klass: VSM::Intelligence, args: {}) = (@roles[:intelligence] = klass.new(**args))
      def operations(klass: VSM::Operations, args: {}, &blk)
        @roles[:operations] = klass.new(**args)
        if blk
          builder = ChildrenBuilder.new
          builder.instance_eval(&blk)
          @children.merge!(builder.result)
        end
      end

      def monitoring(klass: VSM::Monitoring, args: {}) = (@roles[:monitoring] = klass.new(**args))

      def build
        # Inject governance into tool capsules if they accept it
        @children.each_value do |child|
          child.governance = @roles[:governance] if child.respond_to?(:governance=)
        end
        VSM::Capsule.new(name: @name, roles: @roles, children: @children)
      end

      class ChildrenBuilder
        def initialize; @children = {}; end
        def capsule(name, klass:, args: {})
          @children[name.to_s] = klass.new(**args)
        end
        def result = @children
        def method_missing(*) = result
        def respond_to_missing?(*) = true
      end
    end

    def self.define(name, &blk)
      Builder.new(name).tap { |b| b.instance_eval(&blk) }.build
    end
  end
end

