# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "async/rspec"   # provides Async::RSpec helpers
require "securerandom"

# Load the gem under test:
require "vsm"

# Load shared fakes/helpers:
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

