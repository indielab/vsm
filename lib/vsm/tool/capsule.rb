# frozen_string_literal: true
module VSM
  class ToolCapsule
    include ActsAsTool
    attr_writer :governance
    def governance = @governance || (raise "governance not injected")
    # Subclasses implement:
    # def run(args) ... end
    # Optional:
    # def execution_mode = :fiber | :thread
  end
end
