# frozen_string_literal: true

require_relative "meta"
module VSM
  module DSL
    class Builder
      def initialize(name)
        @name = name
        @roles = {}
        @children = {}
        @after_build = []
      end

      def identity(klass: VSM::Identity, args: {})     = assign_role(:identity, klass, args)
      def governance(klass: VSM::Governance, args: {}) = assign_role(:governance, klass, args)
      def coordination(klass: VSM::Coordination, args: {}) = assign_role(:coordination, klass, args)
      def intelligence(klass: VSM::Intelligence, args: {}) = assign_role(:intelligence, klass, args)
      def operations(klass: VSM::Operations, args: {}, &blk)
        @roles[:operations] = instantiate(klass, args)
        if blk
          builder = ChildrenBuilder.new(self)
          builder.instance_eval(&blk)
          @children.merge!(builder.result)
        end
      end

      def monitoring(klass: VSM::Monitoring, args: {}) = assign_role(:monitoring, klass, args)

      def build
        # Inject governance into tool capsules if they accept it
        @children.each_value do |child|
          child.governance = @roles[:governance] if child.respond_to?(:governance=)
        end
        capsule = VSM::Capsule.new(name: @name, roles: @roles, children: @children)
        @after_build.each { _1.call(capsule) }
        capsule
      end

      class ChildrenBuilder
        def initialize(parent)
          @parent = parent
          @children = {}
        end
        def capsule(name, klass:, args: {})
          instance = klass.new(**args)
          VSM::Meta::Support.record_constructor_args(instance, args)
          @children[name.to_s] = instance
        end
        def meta_tools(prefix: "", only: nil, except: nil)
          @parent.__send__(:after_build) do |capsule|
            VSM::Meta.attach!(capsule, prefix: prefix, only: only, except: except)
          end
          result
        end
        def result = @children
        def method_missing(*) = result
        def respond_to_missing?(*) = true
      end

      private

      def after_build(&block)
        @after_build << block if block
      end

      def assign_role(key, klass, args)
        @roles[key] = instantiate(klass, args)
      end

      def instantiate(klass, args)
        instance = klass.new(**args)
        VSM::Meta::Support.record_constructor_args(instance, args)
      end
    end

    def self.define(name, &blk)
      Builder.new(name).tap { |b| b.instance_eval(&blk) }.build
    end
  end
end
