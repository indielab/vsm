# frozen_string_literal: true
require "async"
require "async/http/internet"
require "json"
require "securerandom"

module VSM
  module Drivers
    module Gemini
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://generativelanguage.googleapis.com/v1beta")
          @api_key, @model, @base = api_key, model, base_url
        end

        def run!(conversation:, tools:, policy: {}, &emit)
          internet = Async::HTTP::Internet.new
          begin
              uri = "#{@base}/models/#{@model}:generateContent?key=#{@api_key}"
              headers = { "content-type" => "application/json" }

              contents = to_gemini_contents(conversation, policy[:system_prompt])
              fndecls = normalize_gemini_tools(tools)

              body = JSON.dump({ contents: contents, tools: { function_declarations: fndecls } })
              res  = internet.post(uri, headers, body)

              if res.status != 200
                warn "gemini HTTP #{res.status}: #{res.read}"
                emit.call(:assistant_final, "")
                return :done
              end

              data  = JSON.parse(res.read) rescue {}
              parts = (data.dig("candidates",0,"content","parts") || [])

              calls = parts.filter_map { |p|
                fc = p["functionCall"]
                fc && { id: SecureRandom.uuid, name: fc["name"], arguments: fc["args"] || {} }
              }

              if calls.any?
                emit.call(:tool_calls, calls)
              else
                text = parts.filter_map { |p| p["text"] }.join
                emit.call(:assistant_final, text.to_s)
              end
          ensure
            internet.close
          end
          :done
        end

        private
        def normalize_gemini_tools(tools)
          Array(tools).map { |t| normalize_gemini_tool(t) }
        end

        def normalize_gemini_tool(t)
          return t.to_gemini_tool if t.respond_to?(:to_gemini_tool)

          # Provider-shaped: { name:, description:, parameters: {…} }
          if t.is_a?(Hash) && (t[:parameters] || t["parameters"])
            return t
          end

          # Neutral hash {name:, description:, schema:}
          if t.is_a?(Hash) && (t[:name] || t["name"])
            return {
              name:        t[:name]        || t["name"],
              description: t[:description] || t["description"] || "",
              parameters:  t[:schema]      || t["schema"]      || {}
            }
          end

          raise TypeError, "unsupported tool descriptor: #{t.inspect}"
        end


        def to_gemini_contents(neutral, system_prompt)
          items = []
          items << { role: "user", parts: [{ text: system_prompt }] } if system_prompt
          neutral.each do |m|
            case m[:role]
            when "user"
              items << { role: "user", parts: [{ text: m[:content].to_s }] }
            when "assistant"
              items << { role: "model", parts: [{ text: m[:content].to_s }] }
            when "assistant_tool_calls"
              # Gemini doesn't need us to echo previous functionCall(s)
              # Skip: model will remember its own functionCall
            when "tool_result"
              # Provide functionResponse so model can continue
              name = m[:name] || "tool"
              items << { role: "user", parts: [{ functionResponse: { name: name, response: { content: m[:content].to_s } } }] }
            end
          end
          items
        end
      end
    end
  end
end

