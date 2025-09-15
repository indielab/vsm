# frozen_string_literal: true
require "securerandom"
require "io/console"
require "async"

module VSM
  module Ports
    # Generic, customizable chat TTY port.
    # - Safe to run alongside an MCP stdio port: prefers IO.console for I/O.
    # - Override banner(io) and render_out(message) to customize without
    #   reimplementing the core input loop.
    class ChatTTY < VSM::Port
      DEFAULT_THEME = {
        you:    "\e[94mYou\e[0m: ",
        tool:   "\e[90m→ tool\e[0m ",
        turn:   "\e[2m(turn %s)\e[0m"
      }.freeze

      def initialize(capsule:, input: nil, output: nil, banner: nil, prompt: nil, theme: {})
        super(capsule: capsule)
        # Prefer STDIN/STDOUT if they are TTY. If not, try /dev/tty.
        # Avoid IO.console to minimize kqueue/select issues under async.
        tty_io = nil
        if !$stdout.tty?
          begin
            tty_io = File.open("/dev/tty", "r+")
          rescue StandardError
            tty_io = nil
          end
        end

        @in  = input  || (tty_io || ($stdin.tty?  ? $stdin  : nil))
        @out = output || (tty_io || ($stdout.tty? ? $stdout : $stderr))
        @banner = banner # String or ->(io) {}
        @prompt = prompt || DEFAULT_THEME[:you]
        @theme  = DEFAULT_THEME.merge(theme)
        @streaming = false
      end

      def should_render?(message)
        [:assistant_delta, :assistant, :tool_call, :tool_result].include?(message.kind)
      end

      def loop
        sid = SecureRandom.uuid
        @capsule.roles[:coordination].grant_floor!(sid) if @capsule.roles[:coordination].respond_to?(:grant_floor!)
        banner(@out)

        if @in.nil?
          @out.puts "(no interactive TTY; ChatTTY input disabled)"
          Async::Task.current.sleep # keep task alive for egress rendering
          return
        end

        @out.print @prompt
        while (line = @in.gets&.chomp)
          @capsule.bus.emit VSM::Message.new(kind: :user, payload: line, meta: { session_id: sid })
          if @capsule.roles[:coordination].respond_to?(:wait_for_turn_end)
            @capsule.roles[:coordination].wait_for_turn_end(sid)
          end
          @out.print @prompt
        end
      end

      def render_out(message)
        case message.kind
        when :assistant_delta
          @streaming = true
          @out.print(message.payload)
          @out.flush
        when :assistant
          # If we didn't stream content, print the final content now.
          unless @streaming
            txt = message.payload.to_s
            unless txt.empty?
              @out.puts
              @out.puts txt
            end
          end
          turn = message.meta&.dig(:turn_id)
          @out.puts(@theme[:turn] % turn) if turn
          @streaming = false
        when :tool_call
          @out.puts
          @out.puts "#{@theme[:tool]}#{message.payload[:tool]}"
        when :tool_result
          # Show tool result payload for manual or non-streaming usage.
          out = message.payload.to_s
          unless out.empty?
            @out.puts
            @out.puts out
          end
        end
      end

      # Overridable header/banner
      def banner(io)
        if @banner.respond_to?(:call)
          @banner.call(io)
        elsif @banner.is_a?(String)
          io.puts @banner
        else
          io.puts "vsm chat — Ctrl-C to exit"
        end
      end
    end
  end
end
