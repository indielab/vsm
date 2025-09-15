# frozen_string_literal: true
require "json"
require "monitor"

module VSM
  module MCP
    module JSONRPC
      # Minimal NDJSON (one JSON per line) JSON-RPC transport over IO.
      # Note: MCP servers often speak LSP framing; we can add that later.
      class Stdio
        include MonitorMixin

        def initialize(r:, w:)
          @r = r
          @w = w
          @seq = 0
          mon_initialize
        end

        def request(method, params = {})
          id = next_id
          write({ jsonrpc: "2.0", id: id, method: method, params: params })
          loop do
            msg = read
            next unless msg
            if msg["id"].to_s == id.to_s
              err = msg["error"]
              raise(err.is_a?(Hash) ? (err["message"] || err.inspect) : err.to_s) if err
              return msg["result"]
            end
          end
        end

        def notify(method, params = {})
          write({ jsonrpc: "2.0", method: method, params: params })
        end

        def read
          line = @r.gets
          return nil unless line
          # Handle LSP-style framing: "Content-Length: N" followed by blank line and JSON body.
          if line =~ /\AContent-Length:\s*(\d+)\s*\r?\n?\z/i
            length = Integer($1)
            # Consume optional additional headers until blank line
            while (hdr = @r.gets)
              break if hdr.strip.empty?
            end
            body = read_exact(length)
            $stderr.puts("[mcp-rpc] < #{body}") if ENV["VSM_MCP_DEBUG"] == "1"
            return JSON.parse(body)
          end
          # Otherwise assume NDJSON (one JSON object per line)
          $stderr.puts("[mcp-rpc] < #{line.strip}") if ENV["VSM_MCP_DEBUG"] == "1"
          JSON.parse(line)
        end

        def write(obj)
          body = JSON.dump(obj)
          $stderr.puts("[mcp-rpc] > #{body}") if ENV["VSM_MCP_DEBUG"] == "1"
          synchronize do
            # Prefer NDJSON for broad compatibility; some servers require LSP.
            # If VSM_MCP_LSP=1, use Content-Length framing.
            if ENV["VSM_MCP_LSP"] == "1"
              @w.write("Content-Length: #{body.bytesize}\r\n\r\n")
              @w.write(body)
              @w.flush
            else
              @w.puts(body)
              @w.flush
            end
          end
        end

        private

        def next_id
          synchronize { @seq += 1; @seq.to_s }
        end

        def read_exact(n)
          data = +""
          while data.bytesize < n
            chunk = @r.read(n - data.bytesize)
            break unless chunk
            data << chunk
          end
          data
        end
      end
    end
  end
end
