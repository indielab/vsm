# frozen_string_literal: true
require "json"
require "net/http"
require "uri"
require "securerandom"

module VSM
  module Drivers
    module Anthropic
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://api.anthropic.com/v1", version: "2023-06-01")
          @api_key, @model, @base, @version = api_key, model, base_url, version
        end

        def run!(conversation:, tools:, policy: {}, &emit)
          # Always use Net::HTTP with SSE
          emitted_terminal = false

          headers = {
            "x-api-key" => @api_key,
            "anthropic-version" => @version,
            "content-type" => "application/json",
            "accept" => "text/event-stream"
          }

          messages  = to_anthropic_messages(conversation, policy[:system_prompt])
          tool_list = normalize_anthropic_tools(tools)
          payload = {
            model: @model,
            system: policy[:system_prompt],
            messages: messages,
            max_tokens: 512,
            stream: true
          }
          if tool_list.any?
            payload[:tools] = tool_list
            payload[:tool_choice] = { type: "auto" }
          end
          body = JSON.dump(payload)

          url = URI.parse("#{@base}/messages")
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = (url.scheme == "https")
          http.read_timeout = 120

          req = Net::HTTP::Post.new(url.request_uri)
          headers.each { |k,v| req[k] = v }
          req.body = body

          res = http.request(req) do |response|
            ct = response["content-type"]
            if response.code.to_i != 200
              err_body = +""
              response.read_body { |chunk| err_body << chunk }
              preview = err_body.to_s.byteslice(0, 400)
              emit.call(:assistant_final, "Anthropic HTTP #{response.code}: #{preview}")
              emitted_terminal = true
              next
            end

            if ct && ct.include?("text/event-stream")
              buffer = +""
              textbuf = +""
              toolbuf = {}
              tool_calls = []

              response.read_body do |chunk|
                buffer << chunk
                while (i = buffer.index("\n"))
                  line = buffer.slice!(0..i)
                  line.chomp!
                  next unless line.start_with?("data:")
                  data = line.sub("data:","").strip
                  next if data.empty? || data == "[DONE]"
                  obj = JSON.parse(data) rescue nil
                  next unless obj
                  ev = obj["type"].to_s
                  if ENV["VSM_DEBUG_STREAM"] == "1"
                    $stderr.puts "anthropic(nethttp) <= #{ev}: #{data.byteslice(0, 160)}"
                  end

                  case ev
                  when "content_block_delta"
                    idx = obj["index"]; delta = obj["delta"] || {}
                    case delta["type"]
                    when "text_delta"
                      part = delta["text"].to_s
                      textbuf << part
                      emit.call(:assistant_delta, part)
                    when "input_json_delta"
                      toolbuf[idx] ||= { id: nil, name: nil, json: +"" }
                      toolbuf[idx][:json] << (delta["partial_json"] || "")
                    end
                  when "content_block_start"
                    # For anthropic, the key can be 'content' or 'content_block'
                    c = obj["content"] || obj["content_block"] || {}
                    if c["type"] == "tool_use"
                      name = c["name"] || obj["name"]
                      toolbuf[obj["index"]] = { id: c["id"], name: name, json: +"" }
                    end
                  when "content_block_stop"
                    idx = obj["index"]
                    if tb = toolbuf[idx]
                      args = tb[:json].empty? ? {} : (JSON.parse(tb[:json]) rescue {"_raw"=>tb[:json]})
                      # Only enqueue if name is present
                      if tb[:name].to_s.strip != "" && tb[:id]
                        tool_calls << { id: tb[:id], name: tb[:name], arguments: args }
                      end
                    end
                  when "message_stop"
                    if tool_calls.any?
                      emit.call(:tool_calls, tool_calls)
                    else
                      emit.call(:assistant_final, textbuf.dup)
                    end
                    emitted_terminal = true
                  end
                end
              end

              unless emitted_terminal
                # If the stream closed without a terminal, emit final text
                emit.call(:assistant_final, textbuf)
                emitted_terminal = true
              end
            else
              # Non-streaming JSON
              data = ""
              response.read_body { |chunk| data << chunk }
              obj = JSON.parse(data) rescue {}
              parts = Array(obj.dig("content"))
              calls = []
              text  = +""
              parts.each do |p|
                case p["type"]
                when "text" then text << p["text"].to_s
                when "tool_use" then calls << { id: p["id"] || SecureRandom.uuid, name: p["name"], arguments: p["input"] || {} }
                end
              end
              if calls.any?
                emit.call(:tool_calls, calls)
              else
                emit.call(:assistant_final, text)
              end
              emitted_terminal = true
            end
          end

          :done
        end

        private
        # (no IPv6/IPv4 forcing; rely on default Internet)
        def normalize_anthropic_tools(tools)
          Array(tools).map { |t| normalize_anthropic_tool(t) }
        end

        def normalize_anthropic_tool(t)
          return t.to_anthropic_tool if t.respond_to?(:to_anthropic_tool)

          # Provider-shaped: {name:, description:, input_schema: {…}}
          if t.is_a?(Hash) && (t[:input_schema] || t["input_schema"])
            return t
          end

          # Neutral hash {name:, description:, schema:}
          if t.is_a?(Hash) && (t[:name] || t["name"])
            return {
              name:        t[:name]        || t["name"],
              description: t[:description] || t["description"] || "",
              input_schema: t[:schema]     || t["schema"]      || {}
            }
          end

          raise TypeError, "unsupported tool descriptor: #{t.inspect}"
        end


        def to_anthropic_messages(neutral, _system)
          # Build content blocks per message; keep ordering
          neutral.map do |m|
            case m[:role]
            when "user"
              { role: "user", content: [{ type: "text", text: m[:content].to_s }] }
            when "assistant"
              { role: "assistant", content: [{ type: "text", text: m[:content].to_s }] }
            when "assistant_tool_calls"
              blocks = Array(m[:tool_calls]).map { |c|
                { type: "tool_use", id: c[:id], name: c[:name], input: c[:arguments] || {} }
              }
              { role: "assistant", content: blocks }
            when "tool_result"
              { role: "user", content: [{ type: "tool_result", tool_use_id: m[:tool_call_id], content: m[:content].to_s }] }
            end
          end.compact
        end

        def extract_sse_line!(buffer)
          if (i = buffer.index("\n"))
            line = buffer.slice!(0..i)
            line.chomp!
            return line
          end
          nil
        end
      end
    end
  end
end

