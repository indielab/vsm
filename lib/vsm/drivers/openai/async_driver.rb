# frozen_string_literal: true
require "async"
require "async/http/internet"
require "json"

module VSM
  module Drivers
    module OpenAI
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://api.openai.com/v1")
          @api_key, @model, @base = api_key, model, base_url
        end

        MAX_TOOL_TURNS = 8

        def run!(conversation:, tools:, policy: {}, &emit)
          internet = Async::HTTP::Internet.new
          begin
              headers = {
                "Authorization" => "Bearer #{@api_key}",
                "Content-Type"  => "application/json",
                "Accept"        => "text/event-stream"
              }

              messages = to_openai_messages(conversation, policy[:system_prompt])
              tool_list = normalize_openai_tools(tools)

              req_body = JSON.dump({
                model: @model,
                messages: messages,
                tools: tool_list,
                tool_choice: "auto",
                stream: true
              })
              
              # Debug logging
              if ENV["VSM_DEBUG_STREAM"] == "1"
                $stderr.puts "openai => messages: #{JSON.pretty_generate(messages)}"
                $stderr.puts "openai => tools count: #{tool_list.size}"
              end

              response = internet.post("#{@base}/chat/completions", headers, req_body)

              if response.status != 200
                body = response.read
                warn "openai HTTP #{response.status}: #{body}"
                emit.call(:assistant_final, "")
                return :done
              end

              buffer      = +""
              text_buffer = +""
              tc_partial  = Hash.new { |h,k| h[k] = { id: nil, name: nil, args_str: +"" } }

              response.body.each do |chunk|
                buffer << chunk
                while (line = extract_sse_line!(buffer))
                  next if line.empty? || line.start_with?(":")
                  next unless line.start_with?("data:")
                  data = line.sub("data:","").strip
                  $stderr.puts("openai <= #{data}") if ENV["VSM_DEBUG_STREAM"] == "1"
                  next if data == "[DONE]"

                  obj = JSON.parse(data) rescue nil
                  next unless obj
                  choice = obj.dig("choices",0) || {}
                  delta  = choice["delta"] || {}

                  if (content = delta["content"])
                    text_buffer << content
                    emit.call(:assistant_delta, content)
                  end

                  if (tcs = delta["tool_calls"])
                    tcs.each do |tc|
                      idx  = tc["index"] || 0
                      cell = tc_partial[idx]
                      cell[:id]   ||= tc["id"]
                      fn           = tc["function"] || {}
                      cell[:name] ||= fn["name"] if fn["name"]
                      cell[:args_str] << (fn["arguments"] || "")
                    end
                  end

                  if (fr = choice["finish_reason"])
                    case fr
                    when "tool_calls"
                      calls = tc_partial.keys.sort.map do |i|
                        cell = tc_partial[i]
                        {
                          id:  cell[:id]   || "call_#{i}",
                          name: cell[:name] || "unknown_tool",
                          arguments: safe_json(cell[:args_str])
                        }
                      end
                      tc_partial.clear
                      emit.call(:tool_calls, calls)
                    when "stop", "length", "content_filter"
                      emit.call(:assistant_final, text_buffer.dup)
                      text_buffer.clear
                    end
                  end
                end
              end
          ensure
            internet.close
          end
          :done
        end

        private
        def normalize_openai_tools(tools)
          Array(tools).map { |t| normalize_openai_tool(t) }
        end

        def normalize_openai_tool(t)
          # Case 1: our Descriptor object
          return t.to_openai_tool if t.respond_to?(:to_openai_tool)

          # Case 2: provider-shaped already (OpenAI tools API)
          if (t.is_a?(Hash) && (t[:type] || t["type"]))
            return t
          end

          # Case 3: neutral hash {name:, description:, schema:}
          if t.is_a?(Hash) && (t[:name] || t["name"])
            return {
              type: "function",
              function: {
                name:        t[:name]        || t["name"],
                description: t[:description] || t["description"] || "",
                parameters:  t[:schema]      || t["schema"]      || {}
              }
            }
          end

          raise TypeError, "unsupported tool descriptor: #{t.inspect}"
        end


        def to_openai_messages(neutral, system_prompt)
          msgs = []
          msgs << { role: "system", content: system_prompt } if system_prompt
          neutral.each do |m|
            case m[:role]
            when "user"
              msgs << { role: "user", content: m[:content].to_s }
            when "assistant"
              msgs << { role: "assistant", content: m[:content].to_s }
            when "assistant_tool_calls"
              msg = {
                role: "assistant",
                tool_calls: Array(m[:tool_calls]).map { |c|
                  {
                    id: c[:id],
                    type: "function",
                    function: {
                      name: c[:name],
                      arguments: JSON.dump(c[:arguments] || {})
                    }
                  }
                }
              }
              msgs << msg
              if ENV["VSM_DEBUG_STREAM"] == "1"
                $stderr.puts "OpenAI: Converting assistant_tool_calls: #{msg[:tool_calls].map{|tc| "#{tc[:function][:name]}(#{tc[:id]})"}.join(', ')}"
              end
            when "tool_result"
              msg = {
                role: "tool",
                tool_call_id: m[:tool_call_id],
                content: m[:content].to_s
              }
              msgs << msg
              if ENV["VSM_DEBUG_STREAM"] == "1"
                $stderr.puts "OpenAI: Converting tool_result(#{m[:tool_call_id]}): #{m[:content].to_s.slice(0, 100)}"
              end
            end
          end
          msgs
        end

        def extract_sse_line!(buffer)
          if (i = buffer.index("\n"))
            line = buffer.slice!(0..i)
            line.chomp!
            return line
          end
          nil
        end

        def safe_json(s)
          return {} if s.nil? || s.empty?
          JSON.parse(s)
        rescue JSON::ParserError
          { "_raw" => s }
        end
      end
    end
  end
end

