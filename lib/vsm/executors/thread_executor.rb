# frozen_string_literal: true
module VSM
  module Executors
    module ThreadExecutor
      def self.call(tool, args)
        q = Queue.new
        Thread.new do
          begin
            q << [:ok, tool.run(args)]
          rescue => e
            q << [:err, e]
          end
        end
        tag, val = q.pop
        tag == :ok ? val : raise(val)
      end
    end
  end
end
