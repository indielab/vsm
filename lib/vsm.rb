# frozen_string_literal: true

require "async"
require "async/queue"

require_relative "vsm/version"

require_relative "vsm/message"
require_relative "vsm/async_channel"
require_relative "vsm/homeostat"
require_relative "vsm/observability/ledger"

require_relative "vsm/roles/operations"
require_relative "vsm/roles/coordination"
require_relative "vsm/roles/intelligence"
require_relative "vsm/roles/governance"
require_relative "vsm/roles/identity"

require_relative "vsm/tool/descriptor"
require_relative "vsm/tool/acts_as_tool"
require_relative "vsm/tool/capsule"

require_relative "vsm/executors/fiber_executor"
require_relative "vsm/executors/thread_executor"

require_relative "vsm/capsule"
require_relative "vsm/dsl"
require_relative "vsm/port"
require_relative "vsm/runtime"

require_relative "vsm/drivers/openai/async_driver"
require_relative "vsm/drivers/anthropic/async_driver"
require_relative "vsm/drivers/gemini/async_driver"
require_relative "vsm/drivers/family"

module Vsm
  class Error < StandardError; end
  # Your code goes here...
end
