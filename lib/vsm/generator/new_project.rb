# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'pathname'
require_relative '../version'

module VSM
  module Generator
    class NewProject
      TemplateRoot = File.expand_path('templates', __dir__)

      def self.run(name:, path: nil, git: false, bundle: false, provider: 'openai', model: nil, force: false)
        new(name: name, path: path, git: git, bundle: bundle, provider: provider, model: model, force: force).run
      end

      def initialize(name:, path:, git:, bundle:, provider:, model:, force:)
        @input_name = name
        @target_dir = File.expand_path(path || name)
        @git = git
        @bundle = bundle
        @provider = provider
        @model = model
        @force = force
      end

      def run
        prepare_target_dir!

        # Create directory tree
        mkdirs(
          'exe',
          'bin',
          "lib/#{lib_name}",
          "lib/#{lib_name}/ports",
          "lib/#{lib_name}/tools"
        )

        # Render files
        write('README.md', render('README_md.erb'))
        write('.gitignore', render('gitignore.erb'))
        write('Gemfile', render('Gemfile.erb'))
        write('Rakefile', render('Rakefile.erb'))
        write("#{lib_name}.gemspec", render('gemspec.erb'))

        write("exe/#{exe_name}", render('exe_name.erb'), mode: 0o755)
        write('bin/console', render('bin_console.erb'), mode: 0o755)
        write('bin/setup', render('bin_setup.erb'), mode: 0o755)

        write("lib/#{lib_name}.rb", render('lib_name_rb.erb'))
        write("lib/#{lib_name}/version.rb", render('lib_version_rb.erb'))
        write("lib/#{lib_name}/organism.rb", render('lib_organism_rb.erb'))
        write("lib/#{lib_name}/ports/chat_tty.rb", render('lib_ports_chat_tty_rb.erb'))
        write("lib/#{lib_name}/tools/read_file.rb", render('lib_tools_read_file_rb.erb'))

        post_steps

        puts <<~DONE
          
          Created #{module_name} in #{@target_dir}
          
          Next steps:
            cd #{relative_target}
            bundle install
            bundle exec exe/#{exe_name}
          
          Add tools in lib/#{lib_name}/tools and customize banner in lib/#{lib_name}/ports/chat_tty.rb.
      DONE
      end

      private

      def mkdirs(*dirs)
        dirs.each { |d| FileUtils.mkdir_p(File.join(@target_dir, d)) }
      end

      def write(rel, content, mode: nil)
        full = File.join(@target_dir, rel)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
        File.chmod(mode, full) if mode
      end

      def render(template_name)
        template_path = File.join(TemplateRoot, template_name)
        erb = ERB.new(File.read(template_path), trim_mode: '-')
        erb.result(binding)
      end

      def post_steps
        Dir.chdir(@target_dir) do
          if @git
            system('git', 'init')
            system('git', 'add', '-A')
            system('git', 'commit', '-m', 'init')
          end
          if @bundle
            system('bundle', 'install')
          end
        end
      end

      def prepare_target_dir!
        if Dir.exist?(@target_dir)
          if !@force && !(Dir.children(@target_dir) - %w[. ..]).empty?
            raise "Target directory already exists and is not empty: #{@target_dir} (use --force to overwrite)"
          end
        else
          FileUtils.mkdir_p(@target_dir)
        end
      end

      # --- Template helpers (available via binding) ---

      def module_name
        @module_name ||= @input_name.split(/[-_]/).map { |p| p.gsub(/[^a-zA-Z0-9]/, '').capitalize }.join
      end

      def lib_name
        @lib_name ||= @input_name.downcase.gsub('-', '_')
      end

      def exe_name
        @exe_name ||= @input_name.downcase.gsub('_', '-')
      end

      def env_prefix
        @env_prefix ||= @input_name.gsub('-', '_').upcase
      end

      def vsm_version_constraint
        parts = Vsm::VERSION.split('.')
        "~> #{parts[0]}.#{parts[1]}"
      end

      def provider
        (@provider || 'openai').downcase
      end

      def default_model
        return @model if @model && !@model.empty?
        case provider
        when 'anthropic' then 'claude-3-5-sonnet-latest'
        when 'gemini'    then 'gemini-2.0-flash'
        else 'gpt-4o-mini'
        end
      end

      def relative_target
        Pathname.new(@target_dir).relative_path_from(Pathname.new(Dir.pwd)).to_s rescue @target_dir
      end
    end
  end
end
