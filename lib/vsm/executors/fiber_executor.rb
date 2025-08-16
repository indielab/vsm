# frozen_string_literal: true
module VSM
  module Executors
    module FiberExecutor
      def self.call(tool, args)
        tool.run(args) # runs in current Async task
      end
    end
  end
end
