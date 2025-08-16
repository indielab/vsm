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

        # Yields: [:assistant_delta, text], [:assistant_final, text], [:tool_calls, [{id:,name:,arguments:Hash}]]
        def run!(conversation:, tools:, policy: {}, &emit)
          Async do
            internet = Async::HTTP::Internet.new
            begin
              headers = { "Authorization" => "Bearer #{@api_key}", "Content-Type" => "application/json" }
              body = JSON.dump({
                model: @model, messages: conversation,
                tools: tools, tool_choice: "auto", stream: true
              })
              res = internet.post("#{@base}/chat/completions", headers, body)
              res.read do |chunk|
                chunk.each_line do |line|
                  next unless line.start_with?("data:")
                  data = line.sub("data:","").strip
                  next if data.empty? || data == "[DONE]"
                  obj = JSON.parse(data) rescue nil
                  next unless obj
                  choice = obj.dig("choices",0) || {}
                  if (tcs = choice.dig("delta","tool_calls"))
                    calls = tcs.map { |tc|
                      { id: tc["id"], name: tc.dig("function","name"),
                        arguments: parse_json(tc.dig("function","arguments")) }
                    }
                    emit.call(:tool_calls, calls)
                  elsif (content = choice.dig("delta","content"))
                    emit.call(:assistant_delta, content)
                  end
                  emit.call(:assistant_final, "") if choice["finish_reason"] == "stop"
                end
              end
            ensure
              internet.close
            end
          end
          :done
        end

        private
        def parse_json(s) = s && !s.empty? ? (JSON.parse(s) rescue {"_raw"=>s}) : {}
      end
    end
  end
end

