// SPIKE v4: same multi-session harness that was just proven on a plain page
// (positive control hit a breakpoint and resolved a real on-disk path).
// Only the subject changes: the extension is installed FIRST so its worker and
// page targets exist when js-debug attaches, then a repeating call site is
// driven so a breakpoint bound after startup still gets a hit.
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/entrypoints/tabs/main.tsx`;
const BP_LINE = 9;
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 85000).unref?.();

function connect(label, onReverse) {
  const sock = net.connect(Number(dapPort), "127.0.0.1");
  let seq = 0, buf = Buffer.alloc(0);
  const pending = new Map(), listeners = [], events = [];
  const send = (o) => { const b = JSON.stringify(o); sock.write(`Content-Length: ${Buffer.byteLength(b)}\r\n\r\n${b}`); };
  const api = { label, events,
    ready: new Promise((r) => sock.once("connect", r)),
    request: (command, args = {}, ms = 25000) => new Promise((res) => {
      const m = { seq: ++seq, type: "request", command, arguments: args };
      const t = setTimeout(() => res({ success: false, message: "timeout" }), ms);
      pending.set(m.seq, (r) => { clearTimeout(t); res(r); }); send(m);
    }),
    waitFor: (ev, ms) => new Promise((res, rej) => {
      const hit = events.find((e) => e.event === ev); if (hit) return res(hit);
      const t = setTimeout(() => rej(new Error("timeout")), ms);
      listeners.push({ event: ev, res: (e) => { clearTimeout(t); res(e); } });
    }),
    respond: (req, body = {}) => send({ seq: ++seq, type: "response", request_seq: req.seq, success: true, command: req.command, body }),
  };
  sock.on("data", (chunk) => { buf = Buffer.concat([buf, chunk]);
    for (;;) { const sep = buf.indexOf("\r\n\r\n"); if (sep < 0) break;
      const len = Number(/Content-Length: (\d+)/i.exec(buf.subarray(0, sep).toString())?.[1]);
      if (buf.length < sep + 4 + len) break;
      const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString()); buf = buf.subarray(sep + 4 + len);
      if (msg.type === "response" && pending.has(msg.request_seq)) { pending.get(msg.request_seq)(msg); pending.delete(msg.request_seq); }
      else if (msg.type === "request") onReverse?.(msg, api);
      else if (msg.type === "event") { events.push(msg);
        if (msg.event === "breakpoint" && msg.body?.breakpoint?.verified)
          console.log(`[${label}] BREAKPOINT VERIFIED ->`, JSON.stringify(msg.body.breakpoint));
        for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      } } });
  return api;
}
const children = [];
const BP = { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] };
async function startChild(config) {
  const label = `child${children.length + 1}`;
  const c = connect(label, (req, api) => { if (req.command === "startDebugging") { api.respond(req); startChild(req.arguments.configuration); } });
  config = { ...config, webRoot: `${repoRoot}/apps/extension`, sourceMaps: true,
    resolveSourceMapLocations: null,
    sourceMapPathOverrides: {
      "chrome-extension://*/*": `${repoRoot}/apps/extension/*`,
      "webpack://?:*/*": `${repoRoot}/apps/extension/*`,
      "*": "*",
    } };
  children.push(c); await c.ready;
  await c.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = c.request("attach", config);
  await c.waitFor("initialized", 8000).catch(() => {});
  await c.request("setBreakpoints", BP);
  await c.request("configurationDone"); await p;
  const th = await c.request("threads", {}, 6000);
  console.log(`[${label}] threads:`, JSON.stringify(th.body?.threads ?? []));
  const ls = await c.request("loadedSources", {}, 6000);
  const paths = (ls.body?.sources ?? []).map((x) => x.path ?? x.name);
  console.log(`[${label}] loadedSources: ${paths.length}`);
  paths.filter((p) => /\.tsx?$/.test(p)).slice(0, 6).forEach((p) => console.log("     ", p));
  return c;
}

// 1. Install first, so worker + page targets exist before js-debug attaches.
const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
let cid = 0; const cpend = new Map();
const cdpSend = (method, params = {}, sessionId) => new Promise((res) => {
  const m = { id: ++cid, method, params, ...(sessionId ? { sessionId } : {}) };
  cpend.set(m.id, res); cdp.send(JSON.stringify(m));
});
cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && cpend.has(m.id)) { cpend.get(m.id)(m); cpend.delete(m.id); } });
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
console.log("[cdp] extension installed:", extId);
const { result: { targetId } } = await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId } } = await cdpSend("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 1500));

// 2. Attach js-debug to the already-running extension.
const root = connect("root", (req, api) => {
  if (req.command === "startDebugging") {
    console.log("[root] startDebugging for target");
    api.respond(req); startChild(req.arguments.configuration);
  }
});
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
const rootAttach = root.request("attach", {
  type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort),
  webRoot: `${repoRoot}/apps/extension`, sourceMaps: true, targetSelection: "automatic",
  resolveSourceMapLocations: null, urlFilter: "chrome-extension://*",
});
await root.waitFor("initialized", 8000).catch(() => {});
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
console.log("[root] attach success:", (await rootAttach).success);
await new Promise((r) => setTimeout(r, 2500));

// 3. Drive parseSaveRequest repeatedly from the page, so a late-bound
//    breakpoint in the worker still gets a hit.
await cdpSend("Page.enable", {}, sessionId);
await cdpSend("Page.reload", { ignoreCache: true }, sessionId);
console.log("[cdp] reloaded the extension page to re-run main.tsx");

const all = () => [root, ...children];
await Promise.race([
  ...all().map((c) => c.waitFor("stopped", 28000)),
  new Promise((r) => setTimeout(r, 29000)),
]).catch(() => {});
let hitAny = false;
for (const c of all()) {
  const hit = c.events.find((e) => e.event === "stopped");
  if (!hit) continue;
  hitAny = true;
  console.log(`[${c.label}] *** STOPPED ***`, JSON.stringify(hit.body));
  const st = await c.request("stackTrace", { threadId: hit.body.threadId, levels: 4 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
const allSrc = all().flatMap((c) => c.events.filter((e) => e.event === "loadedSource").map((e) => e.body?.source?.path)).filter(Boolean);
const disk = allSrc.filter((p) => p.startsWith("/") && /\.tsx?$/.test(p));
console.log("[spike] sessions:", children.length, "| stopped:", hitAny ? "YES" : "NO");
console.log("[spike] loadedSource total:", allSrc.length, "| on-disk .ts/.tsx:", disk.length);
console.log("[spike] sample of what js-debug resolved:");
[...new Set(allSrc)].slice(0, 12).forEach((p) => console.log("   ", p));
process.exit(0);
