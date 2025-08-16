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

        # conversation: [{role:, content:}] + tool messages (“tool” role becomes tool_result)
        # tools: [{name:, description:, input_schema: {..}}]
        def run!(conversation:, tools:, policy: {}, &emit)
          Async do
            internet = Async::HTTP::Internet.new
            begin
              headers = {
                "x-api-key" => @api_key, "anthropic-version" => @version, "content-type" => "application/json"
              }
              msgs = coerce_messages(conversation, policy)
              body = JSON.dump({
                model: @model, system: policy[:system_prompt],
                messages: msgs, tools: tools, tool_choice: { type: "auto" }, stream: true
              })
              res = internet.post("#{@base}/messages", headers, body)

              tool_buf = {}
              current_event = nil

              res.read do |chunk|
                chunk.each_line do |line|
                  if line.start_with?("event:")
                    current_event = line.split(":",2)[1].strip
                  elsif line.start_with?("data:")
                    data = line.sub("data:","").strip
                    next if data.empty? || data == "[DONE]"
                    obj = JSON.parse(data) rescue nil
                    next unless obj

                    case current_event
                    when "content_block_start"
                      c = obj["content"] || {}
                      if c["type"] == "tool_use"
                        tool_buf[obj["index"]] = { id: c["id"], name: c["name"], json: "" }
                      end
                    when "content_block_delta"
                      idx = obj["index"]; delta = obj["delta"] || {}
                      case delta["type"]
                      when "text_delta"       then emit.call(:assistant_delta, delta["text"].to_s)
                      when "input_json_delta" then tool_buf[idx][:json] << (delta["partial_json"] || "")
                      end
                    when "content_block_stop"
                      idx = obj["index"]
                      if tb = tool_buf.delete(idx)
                        args = tb[:json].empty? ? {} : (JSON.parse(tb[:json]) rescue {"_raw"=>tb[:json]})
                        emit.call(:tool_calls, [{ id: tb[:id], name: tb[:name], arguments: args }])
                      end
                    when "message_stop"
                      emit.call(:assistant_final, "")
                    end
                  end
                end
              end
            ensure
              internet.close
            end
          end
          :done
        end

        private
        def coerce_messages(conversation, policy)
          conversation.map do |m|
            case m[:role]
            when "tool"
              { role: "user", content: [{ type: "tool_result", tool_use_id: m[:tool_call_id], content: m[:content].to_s }] }
            else
              { role: m[:role], content: [{ type: "text", text: m[:content].to_s }] }
            end
          end
        end
      end
    end
  end
end

