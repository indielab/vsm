# frozen_string_literal: true
require "async"
require "net/http"
require "uri"
require "json"
require "securerandom"

module VSM
  module Drivers
    module Gemini
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://generativelanguage.googleapis.com/v1beta", streaming: true)
          @api_key, @model, @base, @streaming = api_key, model, base_url, streaming
        end

        def run!(conversation:, tools:, policy: {}, &emit)
          contents = to_gemini_contents(conversation)
          fndecls  = normalize_gemini_tools(tools)
          if @streaming
            uri = URI.parse("#{@base}/models/#{@model}:streamGenerateContent?alt=sse&key=#{@api_key}")
            headers = { "content-type" => "application/json", "accept" => "text/event-stream" }
            body = JSON.dump({ contents: contents, system_instruction: (policy[:system_prompt] && { parts: [{ text: policy[:system_prompt] }], role: "user" }), tools: [{ functionDeclarations: fndecls }] })
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "https")
            req = Net::HTTP::Post.new(uri.request_uri)
            headers.each { |k,v| req[k] = v }
            req.body = body
            http.request(req) do |res|
              if res.code.to_i != 200
                err = +""; res.read_body { |c| err << c }
                emit.call(:assistant_final, "Gemini HTTP #{res.code}: #{err.to_s.byteslice(0, 400)}")
                next
              end
              buffer = +""; text = +""; calls = []
              res.read_body do |chunk|
                buffer << chunk
                while (i = buffer.index("\n"))
                  line = buffer.slice!(0..i)
                  line.chomp!
                  next unless line.start_with?("data:")
                  data = line.sub("data:","").strip
                  next if data.empty? || data == "[DONE]"
                  obj = JSON.parse(data) rescue nil
                  next unless obj
                  parts = (obj.dig("candidates",0,"content","parts") || [])
                  parts.each do |p|
                    if (t = p["text"]) && !t.empty?
                      text << t
                      emit.call(:assistant_delta, t)
                    end
                    if (fc = p["functionCall"]) && fc["name"]
                      calls << { id: SecureRandom.uuid, name: fc["name"], arguments: (fc["args"] || {}) }
                    end
                  end
                end
              end
              if calls.any?
                emit.call(:tool_calls, calls)
              else
                emit.call(:assistant_final, text)
              end
            end
          else
            uri = URI.parse("#{@base}/models/#{@model}:generateContent?key=#{@api_key}")
            headers = { "content-type" => "application/json" }
            body = JSON.dump({ contents: contents, system_instruction: (policy[:system_prompt] && { parts: [{ text: policy[:system_prompt] }], role: "user" }), tools: [{ functionDeclarations: fndecls }] })
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "https")
            req = Net::HTTP::Post.new(uri.request_uri)
            headers.each { |k,v| req[k] = v }
            req.body = body
            res = http.request(req)
            if res.code.to_i != 200
              emit.call(:assistant_final, "Gemini HTTP #{res.code}")
            else
              data = JSON.parse(res.body) rescue {}
              parts = (data.dig("candidates",0,"content","parts") || [])
              calls = parts.filter_map { |p| fc = p["functionCall"]; fc && { id: SecureRandom.uuid, name: fc["name"], arguments: fc["args"] || {} } }
              if calls.any?
                emit.call(:tool_calls, calls)
              else
                text = parts.filter_map { |p| p["text"] }.join
                emit.call(:assistant_final, text.to_s)
              end
            end
          end
          :done
        end

        private
        # (no IPv6/IPv4 forcing; rely on default Internet)
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


        def to_gemini_contents(neutral)
          items = []
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

