// SPIKE v3: js-debug is a MULTI-SESSION adapter. The root session owns no
// targets; it asks the client to spawn a child session per target through the
// `startDebugging` reverse request. v1/v2 never answered it, so `threads` was
// always empty - that was a flaw in the harness, not evidence about Chrome.
import net from "node:net";
const [, , dapPort, cdpPort, bpFile, bpLine, mode, extRoot, pageUrl] = process.argv;
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 80000).unref?.();

function connect(label, onReverseRequest) {
  const sock = net.connect(Number(dapPort), "127.0.0.1");
  let seq = 0, buf = Buffer.alloc(0);
  const pending = new Map(), listeners = [], events = [];
  const send = (obj) => { const b = JSON.stringify(obj); sock.write(`Content-Length: ${Buffer.byteLength(b)}\r\n\r\n${b}`); };
  const api = {
    label, events,
    ready: new Promise((r) => sock.once("connect", r)),
    request: (command, args = {}, ms = 25000) => new Promise((res) => {
      const msg = { seq: ++seq, type: "request", command, arguments: args };
      const t = setTimeout(() => res({ success: false, message: "timeout" }), ms);
      pending.set(msg.seq, (r) => { clearTimeout(t); res(r); });
      send(msg);
    }),
    waitFor: (ev, ms) => new Promise((res, rej) => {
      const hit = events.find((e) => e.event === ev); if (hit) return res(hit);
      const t = setTimeout(() => rej(new Error(`${label}: timeout waiting for ${ev}`)), ms);
      listeners.push({ event: ev, res: (e) => { clearTimeout(t); res(e); } });
    }),
    respond: (req, body = {}) => send({ seq: ++seq, type: "response", request_seq: req.seq, success: true, command: req.command, body }),
  };
  sock.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const sep = buf.indexOf("\r\n\r\n"); if (sep < 0) break;
      const len = Number(/Content-Length: (\d+)/i.exec(buf.subarray(0, sep).toString())?.[1]);
      if (buf.length < sep + 4 + len) break;
      const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString());
      buf = buf.subarray(sep + 4 + len);
      if (msg.type === "response" && pending.has(msg.request_seq)) { pending.get(msg.request_seq)(msg); pending.delete(msg.request_seq); }
      else if (msg.type === "request") { onReverseRequest?.(msg, api); }
      else if (msg.type === "event") {
        events.push(msg);
        if (msg.event === "breakpoint") console.log(`[${label}] breakpoint ->`, JSON.stringify(msg.body?.breakpoint));
        for (let i = listeners.length - 1; i >= 0; i--)
          if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      }
    }
  });
  return api;
}

const children = [];
const BP = { source: { path: bpFile }, breakpoints: [{ line: Number(bpLine) }] };

async function startChild(config) {
  const label = `child${children.length + 1}`;
  const child = connect(label, (req, api) => {
    if (req.command === "startDebugging") { api.respond(req); startChild(req.arguments.configuration); }
  });
  children.push(child);
  await child.ready;
  await child.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = child.request("attach", config);
  await child.waitFor("initialized", 8000).catch(() => {});
  const bp = await child.request("setBreakpoints", BP);
  console.log(`[${label}] setBreakpoints ->`, JSON.stringify(bp.body?.breakpoints));
  await child.request("configurationDone");
  await p;
  const th = await child.request("threads", {}, 6000);
  console.log(`[${label}] threads:`, JSON.stringify(th.body?.threads ?? []));
  return child;
}

const root = connect("root", (req, api) => {
  if (req.command === "startDebugging") {
    console.log("[root] startDebugging ->", JSON.stringify(req.arguments?.configuration?.type ?? "?"));
    api.respond(req);
    startChild(req.arguments.configuration);
  }
});
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
const rootAttach = root.request("attach", {
  type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort),
  webRoot: mode === "web" ? extRoot : `${extRoot}/../..`, sourceMaps: true,
  targetSelection: "automatic", resolveSourceMapLocations: null,
  ...(mode !== "web" ? { urlFilter: "chrome-extension://*" } : {}),
});
await root.waitFor("initialized", 8000).catch(() => {});
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
console.log("[root] attach success:", (await rootAttach).success);

if (mode === "web") {
  await fetch(`http://127.0.0.1:${cdpPort}/json/new?${pageUrl}`, { method: "PUT" }).catch(() => {});
} else {
  const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
  const cdp = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((r) => cdp.addEventListener("open", r));
  const extId = await new Promise((res) => {
    cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id === 1) res(m.result.id); });
    cdp.send(JSON.stringify({ id: 1, method: "Extensions.loadUnpacked", params: { path: extRoot } }));
  });
  console.log("[cdp] extension installed:", extId);
  if (mode === "page") cdp.send(JSON.stringify({ id: 2, method: "Target.createTarget", params: { url: `chrome-extension://${extId}/tabs.html` } }));
}

const anyStopped = await Promise.race([
  ...[root, ...children].map((c) => c.waitFor("stopped", 30000).then((e) => ({ c, e }))),
  new Promise((_, rej) => setTimeout(() => rej(new Error("no session stopped")), 31000)),
]).catch((e) => { console.log("[spike]", e.message); return null; });

// children grows as startDebugging fires; re-check every session that exists now.
for (const c of [root, ...children]) {
  const hit = c.events.find((e) => e.event === "stopped");
  if (!hit) continue;
  console.log(`[${c.label}] *** STOPPED ***`, JSON.stringify(hit.body));
  const st = await c.request("stackTrace", { threadId: hit.body.threadId, levels: 3 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
for (const c of [root, ...children]) {
  const ls = await c.request("loadedSources", {}, 6000);
  const srcs = (ls.body?.sources ?? []).map((x) => x.path || x.name);
  console.log(`[${c.label}] loadedSources: ${srcs.length}`, JSON.stringify(srcs.slice(0, 3)));
}
console.log("[spike] sessions spawned:", children.length, "| stopped:", anyStopped ? "YES" : "NO");
process.exit(0);
