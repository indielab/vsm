# frozen_string_literal: true
require "async"
require "async/http/internet"
require "json"
require "net/http"
require "uri"
require "securerandom"

module VSM
  module Drivers
    module Anthropic
      class AsyncDriver
        def initialize(api_key:, model:, base_url: "https://api.anthropic.com/v1", version: "2023-06-01", streaming: true, transport: :async)
          @api_key, @model, @base, @version, @streaming, @transport = api_key, model, base_url, version, streaming, transport
        end

        def run!(conversation:, tools:, policy: {}, &emit)
          # If requested, use Net::HTTP transport (workaround for environments where Async::HTTP can't connect)
          if @transport.to_sym == :nethttp
            return run_with_net_http(conversation:, tools:, policy:, &emit)
          end

          internet = Async::HTTP::Internet.new
          begin
              emitted_terminal = false
              headers = {
                "x-api-key" => @api_key,
                "anthropic-version" => @version,
                "content-type" => "application/json",
                "accept" => (@streaming ? "text/event-stream" : "application/json")
              }

              messages = to_anthropic_messages(conversation, policy[:system_prompt])
              tool_list = normalize_anthropic_tools(tools)

              req_body = JSON.dump({
                model: @model,
                system: policy[:system_prompt],
                messages: messages,
                tools: tool_list,
                tool_choice: { type: "auto" },
                max_tokens: 512,
                stream: !!@streaming
              })

              url = "#{@base}/messages"
              if ENV["VSM_DEBUG_STREAM"] == "1"
                $stderr.puts("anthropic => POST #{url}")
                $stderr.puts("anthropic => headers: #{headers.reject{|k,_| k=="x-api-key"}.inspect}")
                $stderr.puts("anthropic => body keys: #{JSON.parse(req_body).keys}") rescue nil
              end
              response = internet.post(url, headers, req_body)

              if response.status != 200
                body = response.read
                msg = "Anthropic HTTP #{response.status}: #{body.to_s.slice(0, 400)}"
                warn msg
                emit.call(:assistant_final, msg)
                emitted_terminal = true
                return :done
              end

              ct = (response.headers["content-type"] || response.headers["Content-Type"] rescue nil).to_s
              if @streaming && ct.include?("text/event-stream")
                buffer  = +""
                textbuf = +""
                toolbuf = {} # index => { id:, name:, json: "" }
                tool_calls = []
                saw_event = false

                response.body.each do |chunk|
                  buffer << chunk
                  while (line = extract_sse_line!(buffer))
                    next unless line.start_with?("data:")
                    data = line.sub("data:","").strip
                    $stderr.puts("anthropic <= #{data}") if ENV["VSM_DEBUG_STREAM"] == "1"
                    next if data.empty? || data == "[DONE]"
                    obj = JSON.parse(data) rescue nil
                    next unless obj
                    ev = obj["type"].to_s
                    saw_event = true

                    case ev
                    when "message_start"
                      # ignore
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
                    when "message_delta"
                      # ignore or inspect obj["delta"]["stop_reason"]
                    when "message_stop"
                      # Emit exactly one terminal event: prefer tool_calls if present
                      if tool_calls.any?
                        emit.call(:tool_calls, tool_calls)
                        emitted_terminal = true
                      else
                        emit.call(:assistant_final, textbuf.dup)
                        emitted_terminal = true
                      end
                      textbuf.clear
                    else
                      # ignore ping/unknown types
                    end
                  end
                end

                unless emitted_terminal
                  # Fallback: no SSE data received; retry non-streaming once
                  if !saw_event
                    $stderr.puts("anthropic: no SSE events observed; retrying non-streaming") if ENV["VSM_DEBUG_STREAM"] == "1"
                    headers_fallback = headers.merge("accept" => "application/json")
                    res2 = internet.post(url, headers_fallback, req_body)
                    body2 = res2.read
                    data2 = JSON.parse(body2) rescue {}
                    parts2 = Array(data2.dig("content"))
                    calls2 = []
                    text2  = +""
                    parts2.each do |p|
                      case p["type"]
                      when "text" then text2 << p["text"].to_s
                      when "tool_use" then calls2 << { id: p["id"] || SecureRandom.uuid, name: p["name"], arguments: p["input"] || {} }
                      end
                    end
                    if calls2.any?
                      emit.call(:tool_calls, calls2)
                      emitted_terminal = true
                    else
                      emit.call(:assistant_final, text2)
                      emitted_terminal = true
                    end
                  end
                end
              else
                # Non-streaming response
                body = response.read
                data = JSON.parse(body) rescue {}
                # Modern Anthropic messages response: {content:[{type:"text",text:"..."}, {type:"tool_use",...}]}
                parts = Array(data.dig("content"))
                calls = []
                text  = +""
                parts.each do |p|
                  case p["type"]
                  when "text"
                    text << p["text"].to_s
                  when "tool_use"
                    calls << { id: p["id"] || SecureRandom.uuid, name: p["name"], arguments: p["input"] || {} }
                  end
                end
                if calls.any?
                  emit.call(:tool_calls, calls)
                  emitted_terminal = true
                else
                  emit.call(:assistant_final, text)
                  emitted_terminal = true
                end
              end
          rescue => e
            msg = "Anthropic request failed: #{e.class}: #{e.message}"
            warn msg
            emit.call(:assistant_final, msg)
            emitted_terminal = true
          ensure
            unless emitted_terminal
              # Ensure turn ends to prevent hanging waiters
              emit.call(:assistant_final, "")
            end
            internet.close
          end
          :done
        end

        # --- Net::HTTP transport (streaming and non-streaming) ---
        def run_with_net_http(conversation:, tools:, policy: {}, &emit)
          emitted_terminal = false

          headers = {
            "x-api-key" => @api_key,
            "anthropic-version" => @version,
            "content-type" => "application/json",
            "accept" => (@streaming ? "text/event-stream" : "application/json")
          }

          messages  = to_anthropic_messages(conversation, policy[:system_prompt])
          tool_list = normalize_anthropic_tools(tools)
          payload = {
            model: @model,
            system: policy[:system_prompt],
            messages: messages,
            max_tokens: 512,
            stream: !!@streaming
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

            if @streaming && ct && ct.include?("text/event-stream")
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

