# frozen_string_literal: true

require_relative "lib/vsm/version"

Gem::Specification.new do |spec|
  spec.name = "vsm"
  spec.version = Vsm::VERSION
  spec.authors = ["Scott Werner"]
  spec.email = ["scott@sublayer.com"]

  spec.summary = "Async, recursive agent framework for Ruby (Viable System Model): capsules, tools-as-capsules, streaming tool calls, and observability."
  spec.description = <<~DESC
    VSM is a small Ruby framework for building agentic systems using a
    Viable System Model–style architecture. It gives you Capsules: self‑contained components
    composed of five named systems (Operations, Coordination, Intelligence, Governance,
    Identity) plus an async runtime so many capsules can run concurrently.
  DESC

  spec.homepage = "https://github.com/sublayerapp/vsm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/sublayerapp/vsm"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.27"
  spec.add_dependency "async-http", "~> 0.90"
  spec.add_dependency "rack", "~> 3.2"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "async-rspec", "~> 1.17"

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
