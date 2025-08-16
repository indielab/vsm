# frozen_string_literal: true
require "rack"
require "rack/utils"

module VSM
  module Lens
    class Server
      INDEX_HTML = <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>VSM Lens</title>
        <style>
          :root { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; }
          body { margin: 0; background: #0b0f14; color: #cfd8e3; }
          header { padding: 12px 16px; background: #111827; border-bottom: 1px solid #1f2937; display:flex; align-items:center; gap:12px;}
          header .dot { width:10px; height:10px; border-radius:50%; background:#10b981; }
          main { display: grid; grid-template-columns: 280px 1fr; height: calc(100vh - 50px); }
          aside { border-right: 1px solid #1f2937; padding: 12px; overflow:auto;}
          section { padding: 12px; overflow:auto;}
          h2 { font-size: 14px; color:#93c5fd; margin:0 0 8px 0; }
          .card { background:#0f172a; border:1px solid #1f2937; border-radius:8px; padding:10px; margin-bottom:8px;}
          .row { display:flex; align-items:flex-start; gap:8px; padding:8px; border-bottom:1px solid #1f2937; }
          .row:last-child { border-bottom:none; }
          .kind { font-weight:600; min-width:120px; color:#e5e7eb; }
          .meta { color:#9ca3af; font-size:12px; }
          .payload { white-space: pre-wrap; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12px; color:#d1fae5; }
          .pill { display:inline-block; padding:2px 6px; border-radius:999px; font-size:11px; border:1px solid #374151; color:#c7d2fe;}
          .pill.session { color:#fcd34d; }
          .pill.tool { color:#a7f3d0; }
          .toolbar { display:flex; gap:8px; margin-bottom:8px; }
          input[type="text"] { background:#0b1220; color:#e5e7eb; border:1px solid #374151; border-radius:6px; padding:6px 8px; width:100%; }
          .small { font-size:11px; color:#9ca3af; }
        </style>
      </head>
      <body>
        <header><div class="dot"></div><div><strong>VSM Lens</strong> <span class="small">live</span></div></header>
        <main>
          <aside>
            <h2>Sessions</h2>
            <div id="sessions"></div>
            <h2>Filters</h2>
            <div class="card">
              <label class="small">Search</label>
              <input id="filter" type="text" placeholder="text, kind, tool, session…" />
            </div>
          </aside>
          <section>
            <h2>Timeline</h2>
            <div id="timeline"></div>
          </section>
        </main>
        <script>
          const params = new URLSearchParams(window.location.search);
          const es = new EventSource("/events" + (params.get("token") ? ("?token=" + encodeURIComponent(params.get("token"))) : ""));
          const sessions = {};
          const timeline = document.getElementById("timeline");
          const sessionsDiv = document.getElementById("sessions");
          const filterInput = document.getElementById("filter");
          let filter = "";

          filterInput.addEventListener("input", () => { filter = filterInput.value.toLowerCase(); render(); });

          const ring = [];
          const RING_MAX = 1000;

          es.onmessage = (e) => {
            const ev = JSON.parse(e.data);
            ring.push(ev);
            if (ring.length > RING_MAX) ring.shift();

            const sid = ev.meta && ev.meta.session_id;
            if (sid) {
              sessions[sid] = sessions[sid] || { count: 0, last: ev.ts };
              sessions[sid].count += 1; sessions[sid].last = ev.ts;
            }
            render();
          };

          function render() {
            // Sessions
            sessionsDiv.innerHTML = Object.entries(sessions)
              .sort((a,b)=> a[1].last < b[1].last ? 1 : -1)
              .map(([sid, s]) => `<div class="card"><div><span class="pill session">${sid.slice(0,8)}</span></div><div class="small">${s.count} events • last ${s.last}</div></div>`)
              .join("");

            // Timeline
            const rows = ring.filter(ev => {
              if (!filter) return true;
              const hay = JSON.stringify(ev).toLowerCase();
              return hay.includes(filter);
            }).slice(-200).map(ev => row(ev)).join("");

            timeline.innerHTML = rows || "<div class='small'>Waiting for events…</div>";
          }

          function row(ev) {
            const sid = ev.meta && ev.meta.session_id ? `<span class="pill session">${ev.meta.session_id.slice(0,8)}</span>` : "";
            const tool = (ev.kind === "tool_call" && ev.meta && ev.meta.tool) ? `<span class="pill tool">${ev.meta.tool}</span>` : "";
            const path = ev.path ? `<div class="small">path: ${ev.path.join(" › ")}</div>` : "";
            const meta = `<div class="meta">${sid} ${tool} corr:${ev.corr_id || "–"} • ${ev.ts}</div>${path}`;
            const payload = (typeof ev.payload === "string") ? `<div class="payload">${escapeHtml(ev.payload)}</div>` : `<div class="payload">${escapeHtml(JSON.stringify(ev.payload))}</div>`;
            return `<div class="row"><div class="kind">${ev.kind}</div><div>${meta}${payload}</div></div>`;
          }

          function escapeHtml(s) {
            return s.replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
          }
        </script>
      </body>
      </html>
      HTML

      def initialize(hub:, token: nil)
        @hub, @token = hub, token
      end

      def rack_app
        hub = @hub
        token = @token

        Rack::Builder.new do
          use Rack::ContentLength

          map "/" do
            run proc { |_env| [200, { "Content-Type" => "text/html; charset=utf-8" }, [Server::INDEX_HTML]] }
          end

          map "/events" do
            run proc { |env|
              req = Rack::Request.new(env)
              if token && req.params["token"] != token
                [401, { "Content-Type" => "text/plain" }, ["unauthorized"]]
              else
                queue, snapshot = hub.subscribe
                headers = {
                  "Content-Type"  => "text/event-stream",
                  "Cache-Control" => "no-cache",
                  "Connection"    => "keep-alive"
                }
                body = SSEBody.new(hub, queue, snapshot)
                [200, headers, body]
              end
            }
          end
        end
      end

      class SSEBody
        def initialize(hub, queue, snapshot)
          @hub, @queue, @snapshot = hub, queue, snapshot
          @heartbeat = true
        end

        def each
          # Send snapshot first
          @snapshot.each { |ev| yield "data: #{JSON.generate(ev)}\n\n" }
          # Heartbeat thread to keep connections alive
          hb = Thread.new do
            while @heartbeat
              sleep 15
              yield ": ping\n\n"  # SSE comment line
            end
          end
          # Stream live events
          loop do
            ev = @queue.pop
            yield "data: #{JSON.generate(ev)}\n\n"
          end
        ensure
          @heartbeat = false
          @hub.unsubscribe(@queue) rescue nil
          hb.kill if hb&.alive?
        end
      end
    end
  end
end

