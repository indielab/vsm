# VSM — Viable Systems for Ruby Agents

[![Conforms to README.lint](https://img.shields.io/badge/README.lint-conforming-brightgreen)](https://github.com/discoveryworks/readme-dot-lint)

VSM is a tiny, idiomatic Ruby runtime for building agentic systems with a clear spine: Operations, Coordination, Intelligence, Governance, and Identity.

🌸 Why use VSM?
=============================

Building agentic systems often leads to tangled callback spaghetti and unclear responsibilities. As you add tools, LLM providers, and coordination logic, the complexity explodes. You end up with:

- Callbacks nested in callbacks with no clear flow
- Tool execution mixed with business logic
- No clear separation between "what the agent does" vs "how it decides" vs "what rules it follows"
- Difficulty testing individual components
- Lock-in to specific LLM providers or frameworks

VSM solves this by providing a composable, testable architecture with **named responsibilities** (POODR/SOLID style). You get clear separation of concerns from day one, and can start with a single capsule and grow to a swarm—without changing your interface or core loop.

The Viable System Model gives you a proven organizational pattern: every autonomous system needs Operations (doing), Coordination (scheduling), Intelligence (deciding), Governance (rules), and Identity (purpose). VSM makes this concrete in Ruby.

🌸🌸 Who benefits from VSM?
=============================

**Ruby developers building AI agents** who want clean architecture over framework magic. If you've read Sandi Metz's POODR, appreciate small objects with single responsibilities, and want your agent code to be as clean as your Rails models, VSM is for you.

**Teams scaling from prototype to production** who need to start simple (one tool, one LLM call) but know they'll need multiple tools, streaming, confirmations, and policy enforcement later. VSM's recursive capsule design means your "hello world" agent uses the same architecture as your production swarm.

**Developers who want provider independence**. VSM doesn't lock you into OpenAI, Anthropic, or any specific provider. Your Intelligence component decides how to plan—whether that's calling an LLM, following a state machine, or using your own logic.

🌸🌸🌸 What exactly is VSM?
=============================

VSM is a Ruby gem that provides:

1. **Five named systems** that every agent needs:
   - **Operations** — do the work (tools/skills)
   - **Coordination** — schedule, order, and arbitrate conversations (the "floor")
   - **Intelligence** — plan/decide (e.g., call an LLM driver, or your own logic)
   - **Governance** — enforce policy, safety, and budgets
   - **Identity** — define purpose and invariants

2. **Capsules** — recursive building blocks. Every capsule has the five systems above plus a message bus. Capsules can contain child capsules, and "tools" are just capsules that opt-in to a tool interface.

3. **Async-first architecture** — powered by the `async` gem, VSM runs streaming, I/O, and multiple tool calls concurrently without blocking.

4. **Clean interfaces** — Ports translate external events (CLI, HTTP, MCP) into messages. Tools expose JSON Schema descriptors that work with any LLM provider.

5. **Built-in observability** — append-only JSONL ledger of all events, ready to feed into a monitoring UI.

🌸🌸🌸🌸 How do I use VSM?
=============================

## Install

```ruby
# Gemfile
gem "vsm", "~> 0.0.1"
```

```bash
bundle install
```

Ruby 3.2+ recommended.

## Quick Example

Here's a minimal agent with one tool:

```ruby
require "securerandom"
require "vsm"

# 1) Define a tool as a capsule
class EchoTool < VSM::ToolCapsule
  tool_name "echo"
  tool_description "Echoes a message"
  tool_schema({ 
    type: "object", 
    properties: { text: { type: "string" } }, 
    required: ["text"] 
  })

  def run(args)
    "you said: #{args["text"]}"
  end
end

# 2) Define your Intelligence (decides what to do)
class DemoIntelligence < VSM::Intelligence
  def handle(message, bus:, **)
    return false unless message.kind == :user
    
    if message.payload =~ /\Aecho:\s*(.+)\z/
      # User said "echo: something" - call the tool
      bus.emit VSM::Message.new(
        kind: :tool_call,
        payload: { tool: "echo", args: { "text" => $1 } },
        corr_id: SecureRandom.uuid,
        meta: message.meta
      )
    else
      # Just respond
      bus.emit VSM::Message.new(
        kind: :assistant, 
        payload: "Try: echo: hello", 
        meta: message.meta
      )
    end
    true
  end
end

# 3) Build your agent using the DSL
capsule = VSM::DSL.define(:demo) do
  identity     class: VSM::Identity,    args: { identity: "demo", invariants: [] }
  governance   class: VSM::Governance
  coordination class: VSM::Coordination
  intelligence class: DemoIntelligence
  operations do
    capsule :echo, class: EchoTool
  end
end

# 4) Add a simple CLI interface
class StdinPort < VSM::Port
  def loop
    session = SecureRandom.uuid
    print "You: "
    while (line = $stdin.gets&.chomp)
      @capsule.bus.emit VSM::Message.new(
        kind: :user, 
        payload: line, 
        meta: { session_id: session }
      )
      @capsule.roles[:coordination].wait_for_turn_end(session)
      print "You: "
    end
  end

  def render_out(msg)
    case msg.kind
    when :assistant
      puts "\nBot: #{msg.payload}"
    when :tool_result
      puts "\nTool> #{msg.payload}"
      @capsule.bus.emit VSM::Message.new(
        kind: :assistant, 
        payload: "(done)", 
        meta: msg.meta
      )
    end
  end
end

# 5) Start the runtime
VSM::Runtime.start(capsule, ports: [StdinPort.new(capsule:)])
```

Run it:
```bash
ruby quickstart.rb
# You: echo: hello
# Tool> you said: hello
```

## Building a Real Agent

For a real agent with LLM integration:

```ruby
capsule = VSM::DSL.define(:my_agent) do
  identity     class: VSM::Identity, 
               args: { identity: "my_agent", invariants: ["stay in workspace"] }
  governance   class: VSM::Governance
  coordination class: VSM::Coordination
  intelligence class: MyLLMIntelligence  # Your class that calls OpenAI/Anthropic/etc
  monitoring   class: VSM::Monitoring    # Optional: writes JSONL event log
  
  operations do
    capsule :list_files, class: ListFilesTool
    capsule :read_file,  class: ReadFileTool
    capsule :write_file, class: WriteFileTool
  end
end
```

Your `MyLLMIntelligence` would:
1. Maintain conversation history
2. Call your LLM provider with available tools
3. Emit `:tool_call` messages when the LLM wants to use tools
4. Stream `:assistant_delta` tokens as they arrive
5. Emit final `:assistant` message when done

🌸🌸🌸🌸🌸 Extras
=============================

## Table of Contents

- [Features](#features)
- [Core Concepts](#core-concepts)
- [Tools as Capsules](#tools-as-capsules)
- [Async & Parallelism](#async--parallelism)
- [Ports (Interfaces)](#ports-interfaces)
- [Observability](#observability)
- [Writing an Intelligence](#writing-an-intelligence)
- [Testing](#testing)
- [Design Goals](#design-goals)
- [Roadmap](#roadmap)
- [FAQ](#faq)
- [API Overview](#api-overview)
- [License](#license)
- [Contributing](#contributing)

## Features

- **Named systems**: Operations, Coordination, Intelligence, Governance, Identity
- **Capsules**: recursive building blocks (a capsule can contain more capsules)
- **Async bus**: non‑blocking message channel with fan‑out subscribers
- **Structured concurrency**: streaming + multiple tool calls in parallel
- **Tools-as-capsules**: opt‑in tool interface + JSON Schema descriptors
- **Executors**: run tools in the current fiber or a thread pool (Ractor/Subprocess future)
- **Ports**: clean ingress/egress adapters for CLI/TUI/HTTP/MCP/etc.
- **Observability**: append‑only JSONL ledger you can feed into a UI later
- **POODR/SOLID**: small objects, high cohesion, low coupling

## Core Concepts

### Capsule

A container with five named systems and a message bus:

```
Capsule(:name)
├─ Identity      (purpose & invariants)
├─ Governance    (safety & budgets)
├─ Coordination  (scheduling & "floor")
├─ Intelligence  (planning/deciding)
├─ Operations    (tools/skills)
└─ Monitoring    (event ledger; optional)
```

Capsules can contain child capsules. Recursion means a "tool" can itself be a full agent if you want.

### Message

```ruby
VSM::Message.new(
  kind:    :user | :assistant | :assistant_delta | :tool_call | :tool_result | :plan | :policy | :audit | :confirm_request | :confirm_response,
  payload: "any",
  path:    [:airb, :operations, :fs], # optional addressing
  corr_id: "uuid",                     # correlate tool_call ↔ tool_result
  meta:    { session_id: "uuid", ... } # extra context
)
```

### AsyncChannel

A non‑blocking bus built on fibers (`async`). Emitting a message never blocks the emitter.

## Tools as Capsules

Any capsule can opt‑in to act as a "tool" by including `VSM::ActsAsTool` (already included in `VSM::ToolCapsule`).

```ruby
class ReadFile < VSM::ToolCapsule
  tool_name "read_file"
  tool_description "Read the contents of a UTF-8 text file at relative path."
  tool_schema({
    type: "object",
    properties: { path: { type: "string" } },
    required: ["path"]
  })

  def run(args)
    path = governance_safe_path(args.fetch("path"))
    File.read(path, mode: "r:UTF-8")
  end

  # Optional: choose how this tool executes
  def execution_mode = :fiber   # or :thread
  
  private
  
  def governance_safe_path(rel) = governance.instance_eval { # simple helper
    full = File.expand_path(File.join(Dir.pwd, rel))
    raise "outside workspace" unless full.start_with?(Dir.pwd)
    full
  }
end
```

VSM provides provider‑agnostic descriptors:

```ruby
tool = instance.tool_descriptor
tool.to_openai_tool    # => {type:"function", function:{ name, description, parameters }}
tool.to_anthropic_tool # => {name, description, input_schema}
tool.to_gemini_tool    # => {name, description, parameters}
```

**Why opt‑in?** Not every capsule should be callable as a tool. Opt‑in keeps coupling low. Later you can auto‑expose selected capsules as tools or via MCP.

## Async & Parallelism

VSM is async by default:

- The bus is fiber‑based and non‑blocking.
- The capsule loop drains messages without blocking emitters.
- Operations runs each tool call in its own task; tools can choose their execution mode:
  - `:fiber` (default) — I/O‑bound, non‑blocking
  - `:thread` — CPU‑ish work or blocking libraries

You can add Ractor/Subprocess executors later without changing the API.

## Ports (Interfaces)

A Port translates external events into messages and renders outgoing messages. Examples: CLI chat, TUI, HTTP, MCP stdio, editor plugin.

```ruby
class MyPort < VSM::Port
  def loop
    session = SecureRandom.uuid
    while (line = $stdin.gets&.chomp)
      @capsule.bus.emit VSM::Message.new(kind: :user, payload: line, meta: { session_id: session })
      @capsule.roles[:coordination].wait_for_turn_end(session)
    end
  end

  def render_out(msg)
    case msg.kind
    when :assistant_delta then $stdout.print(msg.payload)
    when :assistant       then puts "\nBot: #{msg.payload}"
    when :confirm_request then confirm(msg)
    end
  end

  def confirm(msg)
    print "\nConfirm? #{msg.payload} [y/N] "
    ok = ($stdin.gets || "").strip.downcase.start_with?("y")
    @capsule.bus.emit VSM::Message.new(kind: :confirm_response, payload: { accepted: ok }, meta: msg.meta)
  end
end
```

Start everything:

```ruby
VSM::Runtime.start(capsule, ports: [MyPort.new(capsule:)])
```

## Observability

VSM ships a tiny Monitoring role that writes an append‑only JSONL ledger:

```
.vsm.log.jsonl
{"ts":"2025-08-14T12:00:00Z","kind":"user","path":null,"corr_id":null,"meta":{"session_id":"..."}}
{"ts":"...","kind":"tool_call", ...}
{"ts":"...","kind":"tool_result", ...}
{"ts":"...","kind":"assistant", ...}
```

Use it to power a TUI/HTTP "Lens" later. Because everything flows over the bus, you get consistent events across nested capsules and sub‑agents.

## Writing an Intelligence

The Intelligence role is where you plan/decide. It might:

- forward a conversation to an LLM driver (OpenAI/Anthropic/Gemini),
- emit `:tool_call` messages when the model asks to use tools,
- stream `:assistant_delta` tokens and finish with `:assistant`.

Minimal example (no LLM, just logic):

```ruby
class MyIntelligence < VSM::Intelligence
  def initialize
    @history = Hash.new { |h,k| h[k] = [] }
  end

  def handle(message, bus:, **)
    return false unless [:user, :tool_result].include?(message.kind)
    sid = message.meta&.dig(:session_id)
    @history[sid] << message

    if message.kind == :user && message.payload =~ /read (.+)/
      bus.emit VSM::Message.new(
        kind: :tool_call,
        payload: { tool: "read_file", args: { "path" => $1 } },
        corr_id: SecureRandom.uuid,
        meta: { session_id: sid }
      )
    else
      bus.emit VSM::Message.new(kind: :assistant, payload: "ok", meta: { session_id: sid })
    end
    true
  end
end
```

In your application, you can plug in provider drivers that stream and support native tool calling; Intelligence remains the same.

## Testing

VSM is designed for unit tests:

- **Capsules**: inject fake systems and assert dispatch.
- **Intelligence**: feed `:user` / `:tool_result` messages and assert emitted messages.
- **Tools**: call `#run` directly.
- **Ports**: treat like adapters; they're thin.

Quick smoke test:

```ruby
require "vsm"

RSpec.describe "tool dispatch" do
  class T < VSM::ToolCapsule
    tool_name "t"; tool_description "d"; tool_schema({ type: "object", properties: {}, required: [] })
    def run(_args) = "ok"
  end

  it "routes tool_call to tool_result" do
    cap = VSM::DSL.define(:test) do
      identity     class: VSM::Identity, args: { identity: "t", invariants: [] }
      governance   class: VSM::Governance
      coordination class: VSM::Coordination
      intelligence class: VSM::Intelligence
      operations { capsule :t, class: T }
    end

    q = Queue.new
    cap.bus.subscribe { |m| q << m if m.kind == :tool_result }
    cap.run
    cap.bus.emit VSM::Message.new(kind: :tool_call, payload: { tool: "t", args: {} }, corr_id: "1")
    expect(q.pop.payload).to eq("ok")
  end
end
```

## Design Goals

- **Ergonomic Ruby** (small objects, clear names, blocks/DSL where it helps)
- **High cohesion, low coupling** (roles are tiny; tools are self‑contained)
- **Recursion by default** (any capsule can contain more capsules)
- **Async from day one** (non‑blocking bus; concurrent tools)
- **Portability** (no hard dependency on a specific LLM vendor)
- **Observability built‑in** (event ledger everywhere)

## Roadmap

- [ ] **Executors**: Ractor & Subprocess for heavy/risky tools
- [ ] **Limiter**: per‑tool semaphores and budgets (tokens/time/IO) in Governance
- [ ] **Lens UI**: terminal/HTTP viewer for plans, tools, and audits
- [ ] **Drivers**: optional `vsm-openai`, `vsm-anthropic`, `vsm-gemini` add‑ons for native tool‑calling + streaming
- [ ] **MCP ports**: stdio server/client to expose/consume MCP tools

## FAQ

**Does every capsule have to be a tool?**  
No. Opt‑in via `VSM::ActsAsTool`. Many capsules (planner, auditor, coordinator) shouldn't be callable as tools.

**Can I run multiple interfaces at once (chat + HTTP + MCP)?**  
Yes. Start multiple ports; Coordination arbitrates the "floor" per session.

**How do I isolate risky or CPU‑heavy tools?**  
Set `execution_mode` to `:thread` today. Ractor/Subprocess executors are planned and will use the same API.

**What about streaming tokens?**  
Handled by your Intelligence implementation (e.g., your LLM driver). Emit `:assistant_delta` messages as tokens arrive; finish with a single `:assistant`.

**Is VSM tied to any specific LLM?**  
No. Write a driver that conforms to your Intelligence's expectations (usually "yield deltas" + "yield tool_calls"). Keep the provider in your app gem.

## API Overview

```ruby
module VSM
  # Messages
  Message(kind:, payload:, path: nil, corr_id: nil, meta: {})

  # Bus
  class AsyncChannel
    def emit(message); end
    def pop; end
    def subscribe(&block); end
    attr_reader :context
  end

  # Roles (named systems)
  class Operations;    end  # routes tool_call -> children
  class Coordination;  end  # scheduling, floor, turn-end
  class Intelligence;  end  # your planning/LLM driver
  class Governance;    end  # policy/safety/budgets
  class Identity;      end  # invariants & escalation
  class Monitoring;    end  # JSONL ledger (observe)

  # Capsules & DSL
  class Capsule; end
  module DSL
    def self.define(:name, &block) -> Capsule
  end

  # Tools
  module Tool
    Descriptor#to_openai_tool / #to_anthropic_tool / #to_gemini_tool
  end
  module ActsAsTool; end
  class ToolCapsule
    # include ActsAsTool
    # def run(args) ...
    # def execution_mode = :fiber | :thread
  end

  # Ports & runtime
  class Port
    def initialize(capsule:); end
    def loop; end           # optional
    def render_out(msg); end
    def egress_subscribe; end
  end

  module Runtime
    def self.start(capsule, ports: [])
  end
end
```

## License

MIT. See LICENSE.txt.

## Contributing

Issues and PRs are welcome! Please include:

- A failing spec (RSpec) for bug reports
- Minimal API additions
- Clear commit messages

Run tests with:

```bash
bundle exec rspec
```

Lint with:

```bash
bundle exec rubocop
```
