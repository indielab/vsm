# frozen_string_literal: true

require 'optparse'
require_relative 'generator/new_project'

module VSM
  class CLI
    def self.start(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      cmd = argv.shift
      case cmd
      when 'new'
        run_new(argv)
      when nil, '-h', '--help', 'help'
        puts help_text
      else
        warn "Unknown command: #{cmd}\n"
        puts help_text
        exit 1
      end
    end

    private

    def run_new(argv)
      opts = {
        path: nil,
        git: false,
        bundle: false,
        provider: 'openai',
        model: nil,
        force: false
      }
      parser = OptionParser.new do |o|
        o.banner = "Usage: vsm new <name> [options]"
        o.on('--path PATH', 'Target directory (default: ./<name>)') { |v| opts[:path] = v }
        o.on('--git', 'Run git init and initial commit') { opts[:git] = true }
        o.on('--bundle', 'Run bundle install after generation') { opts[:bundle] = true }
        o.on('--with-llm PROVIDER', %w[openai anthropic gemini], 'LLM provider: openai (default), anthropic, or gemini') { |v| opts[:provider] = v }
        o.on('--model NAME', 'Default model name') { |v| opts[:model] = v }
        o.on('--force', 'Overwrite existing directory') { opts[:force] = true }
        o.on('-h', '--help', 'Show help') { puts o; exit 0 }
      end

      name = nil
      begin
        parser.order!(argv)
        name = argv.shift
      rescue OptionParser::ParseError => e
        warn e.message
        puts parser
        exit 1
      end

      unless name && !name.strip.empty?
        warn 'Please provide a project name, e.g., vsm new my_app'
        puts parser
        exit 1
      end

      VSM::Generator::NewProject.run(name: name, **opts)
    end

    def help_text
      <<~TXT
        VSM CLI

        Commands:
          vsm new <name> [options]   Create a new VSM app skeleton

        Run `vsm new --help` for options.
      TXT
    end
  end
end
