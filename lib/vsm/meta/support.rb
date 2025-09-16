# frozen_string_literal: true

module VSM
  module Meta
    module Support
      CONFIG_IVAR = :@__vsm_constructor_args

      module_function

      def record_constructor_args(instance, args)
        copied = copy_args(args)
        instance.instance_variable_set(CONFIG_IVAR, copied)
        instance
      end

      def fetch_constructor_args(instance)
        instance.instance_variable_get(CONFIG_IVAR)
      end

      def copy_args(args)
        return {} if args.nil?
        case args
        when Hash
          args.transform_values { copy_args(_1) }
        when Array
          args.map { copy_args(_1) }
        when Symbol, Numeric, NilClass, TrueClass, FalseClass
          args
        else
          args.dup rescue args
        end
      end
    end
  end
end
