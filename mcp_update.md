# MCP Integration Plan and Built‑In Ports

This document proposes minimal, practical support to:
- Expose any VSM capsule as an MCP server over stdio (JSON‑RPC) implementing `tools/list` and `tools/call`.
- Add two reusable ports to VSM: a generic, customizable Chat TTY port and an MCP stdio server port.
- Dynamically reflect tools from external MCP servers and wrap them as VSM tool capsules.

The design uses Ruby’s dynamic capabilities and integrates cleanly with existing VSM roles (Operations, Intelligence, Governance, etc.).

## Scope (Phase 1)
- MCP methods: `tools/list`, `tools/call` only.
- Transport: JSON‑RPC over stdio (NDJSON framing to start; can evolve to LSP framing without API changes).
- No additional MCP features (Prompts/Resources/Logs) in this phase.

## Components
- `VSM::Ports::ChatTTY` — Generic, customizable chat terminal port.
- `VSM::Ports::MCP::ServerStdio` — MCP server over stdio exposing capsule tools.
- `VSM::MCP::Client` — Thin stdio JSON‑RPC client for MCP reflection and calls.
- `VSM::MCP::RemoteToolCapsule` — Wraps a remote MCP tool as a local VSM `ToolCapsule`.
- `VSM::DSL::ChildrenBuilder#mcp_server` — Reflect and register remote tools with include/exclude/prefix controls.
- (Tiny core tweak) Inject `bus` into children that accept `bus=` to allow rich observability from wrappers.

## Design Overview
- Client reflection: spawn an MCP server process, call `tools/list`, build `RemoteToolCapsule`s per tool, and add them as children. Include/exclude/prefix options shape the local tool namespace.
- Server exposure: reflect local tools via `tools/list`; on `tools/call`, emit a normal VSM `:tool_call` and await matching `:tool_result` (corr_id = JSON‑RPC id) to reply.
- Operations routing: unchanged for Phase 1. Reflected tools register as regular children; prefixing avoids collisions. (Optional namespacing router can be added later.)
- Observability: all bridges emit events into the bus so Lens shows clear lanes (client: `[:mcp, :client, server, tool]`; server: `[:mcp, :server, tool]`).
- Coexistence: ChatTTY targets the user’s real TTY (e.g., `IO.console`) or stderr; MCP server uses stdio exclusively. They can run together without interfering.

## File Layout (proposed)
- `lib/vsm/ports/chat_tty.rb`
- `lib/vsm/ports/mcp/server_stdio.rb`
- `lib/vsm/mcp/jsonrpc.rb` (shared stdio JSON‑RPC util)
- `lib/vsm/mcp/client.rb`
- `lib/vsm/mcp/remote_tool_capsule.rb`
- `lib/vsm/dsl_mcp.rb` (adds `mcp_server` to the DSL ChildrenBuilder)
- (Core) optional `bus` injection in `lib/vsm/capsule.rb`

## APIs and Usage

### Expose a Capsule via CLI and MCP (simultaneously)
```ruby
require "vsm"
require "vsm/ports/chat_tty"
require "vsm/ports/mcp/server_stdio"

cap = VSM::DSL.define(:demo) do
  identity     klass: VSM::Identity,    args: { identity: "demo", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: VSM::Drivers::OpenAI::AsyncDriver.new(api_key: ENV["OPENAI_API_KEY"], model: "gpt-4o-mini") }
  monitoring   klass: VSM::Monitoring
  operations do
    # local tools …
  end
end

ports = [
  VSM::Ports::MCP::ServerStdio.new(capsule: cap),               # machine IO (stdio)
  VSM::Ports::ChatTTY.new(capsule: cap)                          # human IO (TTY/console)
]
VSM::Runtime.start(cap, ports: ports)
```

### Mount a Remote MCP Server (dynamic reflection)
```ruby
require "vsm"
require "vsm/dsl_mcp"

cap = VSM::DSL.define(:with_remote) do
  identity     klass: VSM::Identity,    args: { identity: "with_remote", invariants: [] }
  governance   klass: VSM::Governance
  coordination klass: VSM::Coordination
  intelligence klass: VSM::Intelligence, args: { driver: VSM::Drivers::Anthropic::AsyncDriver.new(api_key: ENV["ANTHROPIC_API_KEY"], model: "claude-sonnet-4.0") }
  monitoring   klass: VSM::Monitoring
  operations do
    mcp_server :smith, cmd: "smith-server --stdio", include: %w[search read], prefix: "smith_", env: { "SMITH_TOKEN" => ENV["SMITH_TOKEN"] }
  end
end

VSM::Runtime.start(cap, ports: [VSM::Ports::ChatTTY.new(capsule: cap)])
```

### Filter Tools Offered to the Model (optional)
```ruby
class GuardedIntel < VSM::Intelligence
  def offer_tools?(sid, descriptor)
    descriptor.name.start_with?("smith_") # only offer smith_* tools
  end
end
```

## Customization (ChatTTY)
- Constructor options: `input:`, `output:`, `banner:`, `prompt:`, `theme:`.
- Defaults: reads/writes to `IO.console` if available; otherwise reads are disabled and output goes to a safe stream (stderr/console). Never interferes with MCP stdio.
- Override points: subclass and override `banner(io)` and/or `render_out(message)` while reusing the main input loop.

Example (options only):
```ruby
tty = VSM::Ports::ChatTTY.new(
  capsule: cap,
  banner: ->(io) { io.puts "\e[96mMy App\e[0m — welcome!" },
  prompt: "Me> "
)
```

Example (subclass):
```ruby
class FancyTTY < VSM::Ports::ChatTTY
  def banner(io)
    io.puts "\e[95m\n ███  MY APP  ███\n\e[0m"
  end
  def render_out(m)
    super
    @out.puts("\e[92m✓ #{m.payload.to_s.slice(0,200)}\e[0m") if m.kind == :tool_result
  end
end
```

## Coexistence and IO Routing
- MCP stdio server: reads `$stdin`, writes `$stdout` with strict JSON (one message per line). No TTY assumptions.
- ChatTTY: prefers `IO.console` for both input and output; falls back to `$stderr` for output and disables input if no TTY is present.
- Result: Both ports can run in the same process without corrupting MCP stdio.

## Observability
- Client wrapper emits `:progress`/`:audit` with `path: [:mcp, :client, server, tool]` around calls.
- Server port emits `:audit` and wraps `tools/call` into standard `:tool_call`/`:tool_result` with `corr_id` mirrored to JSON‑RPC id.
- Lens will show clear lanes and full payloads, subject to Governance redaction (if any).

## Governance and Operations
- Operations: unchanged; executes capsules for `:tool_call` and emits `:tool_result`.
- Governance: gate by name/prefix/regex; apply timeouts/rate limits/confirmations; redact args/results in Lens if needed.
- Execution mode: remote wrappers default to `:thread` to avoid blocking the reactor on stdio I/O.

## Configuration and Authentication
- Default via ENV (e.g., tokens/keys). Per‑mount overrides available through `mcp_server env: { … }`.
- CLI flags can be introduced later in a helper script if needed.

## Backward Compatibility
- No changes to `airb`. `VSM::Ports::ChatTTY` is a reusable, minimal alternative for new apps.

## Future Extensions (not in Phase 1)
- Namespaced mounts (`smith.search`) with a tiny router enhancement in Operations.
- Code generation flow (`vsm mcp import …`) to create durable wrappers.
- Additional MCP features (prompts/resources/logs) and WebSocket transport.
- Web interaction port: HTTP chat with customizable UI surfaces.

## Milestones
1) Implement ports and client/wrapper (files above), plus optional `bus` injection.
2) Add small README/usage and example snippet in `examples/`.
3) Manual tests: 
   - Start capsule with both ChatTTY and MCP ports; verify no IO collision.
   - Reflect a known MCP server; verify tool listing and calls.
   - Lens shows client/server lanes with corr_id continuity.
4) Optional: DSL include/exclude/prefix validation and guardrails.

## Acceptance Criteria
- Starting a capsule with `VSM::Ports::MCP::ServerStdio` exposes working `tools/list` and `tools/call` on stdio.
- Starting a capsule with `VSM::Ports::ChatTTY` provides a working chat loop; banner/prompt are overridable without re‑implementing the loop.
- Running both ports concurrently does not corrupt MCP stdio.
- Reflecting a remote MCP server via `mcp_server` registers local tool capsules that work with `Intelligence` tool‑calling.
- Lens displays meaningful events for both client and server paths.
