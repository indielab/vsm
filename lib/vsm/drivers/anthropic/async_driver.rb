# frozen_string_literal: true
require "async"
require "async/http/internet"
require "json"

module VSM
  module Drivers
    module Anthropic
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://api.anthropic.com/v1", version: "2023-06-01")
          @api_key, @model, @base, @version = api_key, model, base_url, version
        end

        def run!(conversation:, tools:, policy: {}, &emit)
          internet = Async::HTTP::Internet.new
          begin
              headers = {
                "x-api-key" => @api_key,
                "anthropic-version" => @version,
                "content-type" => "application/json",
                "accept" => "text/event-stream"
              }

              messages = to_anthropic_messages(conversation, policy[:system_prompt])
              tool_list = normalize_anthropic_tools(tools)

              req_body = JSON.dump({
                model: @model,
                system: policy[:system_prompt],
                messages: messages,
                tools: tool_list,
                tool_choice: { type: "auto" },
                stream: true
              })

              response = internet.post("#{@base}/messages", headers, req_body)

              if response.status != 200
                body = response.read
                warn "anthropic HTTP #{response.status}: #{body}"
                emit.call(:assistant_final, "")
                return :done
              end

              event   = nil
              buffer  = +""
              textbuf = +""
              toolbuf = {} # index => { id:, name:, json: "" }
              tool_calls = []

              response.body.each do |chunk|
                buffer << chunk
                while (line = extract_sse_line!(buffer))
                  if line.start_with?("event:")
                    event = line.split(":",2)[1].strip
                    $stderr.puts("anthropic <= event: #{event}") if ENV["VSM_DEBUG_STREAM"] == "1"
                    next
                  end
                  next unless line.start_with?("data:")
                  data = line.sub("data:","").strip
                  $stderr.puts("anthropic <= #{event} #{data}") if ENV["VSM_DEBUG_STREAM"] == "1"
                  next if data.empty? || data == "[DONE]"
                  obj = JSON.parse(data) rescue nil
                  next unless obj

                  case event
                  when "content_block_start"
                    c = obj["content"] || {}
                    if c["type"] == "tool_use"
                      toolbuf[obj["index"]] = { id: c["id"], name: c["name"], json: +"" }
                    end
                  when "content_block_delta"
                    idx = obj["index"]; delta = obj["delta"] || {}
                    case delta["type"]
                    when "text_delta"
                      part = delta["text"].to_s
                      textbuf << part
                      emit.call(:assistant_delta, part)
                    when "input_json_delta"
                      toolbuf[idx][:json] << (delta["partial_json"] || "")
                    end
                  when "content_block_stop"
                    idx = obj["index"]
                    if tb = toolbuf[idx]
                      args = tb[:json].empty? ? {} : (JSON.parse(tb[:json]) rescue {"_raw"=>tb[:json]})
                      tool_calls << { id: tb[:id], name: tb[:name], arguments: args }
                    end
                  when "message_stop"
                    # Emit exactly one terminal event: prefer tool_calls if present
                    if tool_calls.any?
                      emit.call(:tool_calls, tool_calls)
                    else
                      emit.call(:assistant_final, textbuf.dup)
                    end
                    textbuf.clear
                  end
                end
              end
          ensure
            internet.close
          end
          :done
        end

        private
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

