# frozen_string_literal: true
require "set"
require_relative "../drivers/family"

module VSM
  # Orchestrates multi-turn LLM chat with native tool-calls:
  # - Maintains neutral conversation history per session_id
  # - Talks to a provider driver that yields :assistant_delta, :assistant_final, :tool_calls
  # - Emits :tool_call to Operations, waits for ALL results, then continues
  #
  # App authors can subclass and only customize:
  #   - system_prompt(session_id) -> String
  #   - offer_tools?(session_id, descriptor) -> true/false (filter tools)
  class Intelligence
    def initialize(driver:, system_prompt: nil)
      @driver         = driver
      @system_prompt  = system_prompt
      @sessions       = Hash.new { |h,k| h[k] = new_session_state }
    end

    def observe(bus); end

    def handle(message, bus:, **)
      case message.kind
      when :user
        sid = message.meta&.dig(:session_id)
        st  = state(sid)
        st[:history] << { role: "user", content: message.payload.to_s }
        invoke_model(sid, bus)
        true

      when :tool_result
        sid = message.meta&.dig(:session_id)
        st  = state(sid)
        # map id -> tool name if we learned it earlier (useful for Gemini)
        name = st[:tool_id_to_name][message.corr_id]
        
        # Debug logging
        if ENV["VSM_DEBUG_STREAM"] == "1"
          $stderr.puts "Intelligence: Received tool_result for #{name}(#{message.corr_id}): #{message.payload.to_s.slice(0, 100)}"
        end
        
        st[:history] << { role: "tool_result", tool_call_id: message.corr_id, name: name, content: message.payload.to_s }
        st[:pending_tool_ids].delete(message.corr_id)
        # Only continue once all tool results for this turn arrived:
        if st[:pending_tool_ids].empty?
          # Re-enter model for the same turn with tool results in history:
          invoke_model(sid, bus)
        end
        true

      else
        false
      end
    end

    # --- Extension points for apps ---

    # Override to compute a dynamic prompt per session
    def system_prompt(session_id)
      @system_prompt
    end

    # Override to filter tools the model may use (by descriptor)
    def offer_tools?(session_id, descriptor)
      true
    end

    private

    def new_session_state
      {
        history: [],
        pending_tool_ids: Set.new,
        tool_id_to_name: {},
        inflight: false,
        turn_seq: 0
      }
    end

    def state(sid) = @sessions[sid]

    def invoke_model(session_id, bus)
      st = state(session_id)
      if st[:inflight] || !st[:pending_tool_ids].empty?
        if ENV["VSM_DEBUG_STREAM"] == "1"
          $stderr.puts "Intelligence: skip invoke sid=#{session_id} inflight=#{st[:inflight]} pending=#{st[:pending_tool_ids].size}"
        end
        return
      end
      st[:inflight] = true
      st[:turn_seq] += 1
      current_turn_id = st[:turn_seq]

      # Discover tools available from Operations children:
      descriptors, name_index = tool_inventory(bus, session_id)

      # Debug logging
      if ENV["VSM_DEBUG_STREAM"] == "1"
        $stderr.puts "Intelligence: invoke_model sid=#{session_id} inflight=#{st[:inflight]} pending=#{st[:pending_tool_ids].size} turn_seq=#{st[:turn_seq]}"
        $stderr.puts "Intelligence: Calling driver with #{st[:history].size} history entries"
        st[:history].each_with_index do |h, i|
          $stderr.puts "  [#{i}] #{h[:role]}: #{h[:role] == 'assistant_tool_calls' ? h[:tool_calls].map{|tc| "#{tc[:name]}(#{tc[:id]})"}.join(', ') : h[:content]&.slice(0, 100)}"
        end
      end

      task = Async do
        begin
          @driver.run!(
            conversation: st[:history],
            tools: descriptors,
            policy: { system_prompt: system_prompt(session_id) }
          ) do |event, payload|
            case event
            when :assistant_delta
              # optionally buffer based on stream_policy
              bus.emit VSM::Message.new(kind: :assistant_delta, payload: payload, meta: { session_id: session_id, turn_id: current_turn_id })
            when :assistant_final
              unless payload.to_s.empty?
                st[:history] << { role: "assistant", content: payload.to_s }
              end
              bus.emit VSM::Message.new(kind: :assistant, payload: payload, meta: { session_id: session_id, turn_id: current_turn_id })
            when :tool_calls
              st[:history] << { role: "assistant_tool_calls", tool_calls: payload }
              st[:pending_tool_ids] = Set.new(payload.map { _1[:id] })
              payload.each { |c| st[:tool_id_to_name][c[:id]] = c[:name] }
              if ENV["VSM_DEBUG_STREAM"] == "1"
                $stderr.puts "Intelligence: tool_calls count=#{payload.size}; pending now=#{st[:pending_tool_ids].size}"
              end
              # Allow next invocation (after tools complete) without waiting for driver ensure
              st[:inflight] = false
              payload.each do |call|
                bus.emit VSM::Message.new(
                  kind: :tool_call,
                  payload: { tool: call[:name], args: call[:arguments] },
                  corr_id: call[:id],
                  meta: { session_id: session_id, tool: call[:name], turn_id: current_turn_id }
                )
              end
            end
          end
        ensure
          if ENV["VSM_DEBUG_STREAM"] == "1"
            $stderr.puts "Intelligence: driver completed sid=#{session_id}; pending=#{st[:pending_tool_ids].size}; inflight->false"
          end
          st[:inflight] = false
        end
      end
      st[:task] = task
    end

    # Return [descriptors:Array<VSM::Tool::Descriptor>, index Hash{name=>capsule}]
    def tool_inventory(bus, session_id)
      ops = bus.context[:operations_children] || {}
      descriptors = []
      index = {}
      ops.each do |name, capsule|
        next unless capsule.respond_to?(:tool_descriptor)
        desc = capsule.tool_descriptor
        next unless offer_tools?(session_id, desc)
        descriptors << desc
        index[desc.name] = capsule
      end
      [descriptors, index]
    end
  end
end

