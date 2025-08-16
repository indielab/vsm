# frozen_string_literal: true
require "io/console"
require "json"

module VSM
  module Lens
    module TUI
      # Start a simple TUI that renders the last N events and sessions.
      # Usage:
      #   hub = VSM::Lens.attach!(capsule)
      #   VSM::Lens::TUI.start(hub)
      def self.start(hub, ring_max: 500)
        queue, snapshot = hub.subscribe
        ring = snapshot.last(ring_max)

        reader = Thread.new do
          loop { ring << queue.pop; ring.shift if ring.size > ring_max }
        end

        trap("INT")  { exit }
        trap("TERM") { exit }

        STDIN.raw do
          loop do
            draw(ring)
            # Non-blocking single-char read; press 'q' to quit
            ch = if IO.select([STDIN], nil, nil, 0.1) then STDIN.read_nonblock(1) rescue nil end
            exit if ch == "q"
          end
        end
      ensure
        reader&.kill
      end

      def self.draw(ring)
        cols, rows = IO.console.winsize.reverse # => [rows, cols]
        rows ||= 24; cols ||= 80
        system("printf", "\e[2J\e[H") # clear

        # Split: left sessions, right timeline
        left_w  = [28, cols * 0.3].max.to_i
        right_w = cols - left_w - 1
        puts header("VSM Lens TUI — press 'q' to quit", cols)

        # Sessions (left)
        sessions = Hash.new { |h,k| h[k] = { count: 0, last: "" } }
        ring.each do |ev|
          sid = ev.dig(:meta, :session_id) or next
          sessions[sid][:count] += 1
          sessions[sid][:last]   = ev[:ts]
        end
        sess_lines = sessions.sort_by { |_id, s| s[:last].to_s }.reverse.first(rows-3).map do |sid, s|
          "#{sid[0,8]}  #{s[:count].to_s.rjust(5)}  #{s[:last]}"
        end

        puts box("Sessions", sess_lines, left_w)

        # Timeline (right)
        tl = ring.last(rows-3).map do |ev|
          kind = ev[:kind].to_s.ljust(16)
          sid  = ev.dig(:meta, :session_id)&.slice(0,8) || "–"
          txt  = case ev[:payload]
                 when String then ev[:payload].gsub(/\s+/, " ")[0, right_w-40]
                 else ev[:payload].to_s[0, right_w-40]
                 end
          "#{ev[:ts]}  #{kind} #{sid}  #{txt}"
        end
        puts box("Timeline", tl, right_w)
      end

      def self.header(text, width)
        "\e[7m #{text.ljust(width-2)} \e[0m"
      end

      def self.box(title, lines, width)
        out  = +"+" + "-"*(width-2) + "+\n"
        out << "| #{title.ljust(width-4)} |\n"
        out << "+" + "-"*(width-2) + "+\n"
        lines.each do |l|
          out << "| #{l.ljust(width-4)} |\n"
        end
        out << "+" + "-"*(width-2) + "+\n"
        out
      end
    end
  end
end

