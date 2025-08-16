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
          Async do
            internet = Async::HTTP::Internet.new
            begin
              uri = "#{@base}/models/#{@model}:generateContent?key=#{@api_key}"
              headers = { "content-type" => "application/json" }
              body = JSON.dump({ contents: to_gemini_contents(conversation), tools: { function_declarations: tools } })
              res  = internet.post(uri, headers, body)
              data = JSON.parse(res.read) rescue {}

              parts = (data.dig("candidates",0,"content","parts") || [])
              calls = parts.filter_map { |p| fc = p["functionCall"]; fc && { id: SecureRandom.uuid, name: fc["name"], arguments: fc["args"] || {} } }
              if calls.any?
                emit.call(:tool_calls, calls)
              else
                text = parts.filter_map { |p| p["text"] }.join
                emit.call(:assistant_final, text.to_s)
              end
            ensure
              internet.close
            end
          end
          :done
        end

        private
        def to_gemini_contents(conversation)
          conversation.map do |m|
            case m[:role]
            when "user"      then { role: "user",  parts: [{ text: m[:content].to_s }] }
            when "assistant" then { role: "model", parts: [{ text: m[:content].to_s }] }
            when "tool"      then { role: "user",  parts: [{ functionResponse: { name: m[:name] || "tool", response: { content: m[:content] } } }] }
            else                  { role: "user",  parts: [{ text: m[:content].to_s }] }
            end
          end
        end
      end
    end
  end
end

