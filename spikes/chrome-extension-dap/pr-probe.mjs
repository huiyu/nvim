// SPIKE round 5: test vscode-js-debug PR #2361 (extensionPath) in ATTACH mode.
// Deliberately passes ONLY `extensionPath` -- no hand-tuned webRoot or
// sourceMapPathOverrides -- so this measures whether the PR makes the config
// simple, not just whether it can be forced to work.
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/src/features/save-all/save-request.ts`;
const BP_LINE = 11;
setTimeout(() => { console.log("[spike] TIMEOUT"); process.exit(3); }, 90000).unref?.();

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
        if (msg.event === "breakpoint" && msg.body?.breakpoint?.verified) console.log(`  [${label}] BREAKPOINT VERIFIED`);
        if (msg.event === "output" && /error/i.test(String(msg.body?.output ?? ""))) console.log(`  [${label}] err:`, JSON.stringify(msg.body?.data ?? {}).slice(0, 200));
        for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      } } });
  return api;
}

// THE POINT OF THIS TEST: extensionPath and nothing else.
const prConfig = { extensionPath: extRoot };
const children = [];
const BP = { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] };
const reverse = (req, api) => { api.respond(req); if (req.command === "startDebugging") startChild(req.arguments.configuration); };
async function startChild(config) {
  const label = `child${children.length + 1}`;
  const c = connect(label, reverse);
  children.push(c); await c.ready;
  await c.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = c.request("attach", { ...config, ...prConfig });
  await c.waitFor("initialized", 8000).catch(() => {});
  const bp = await c.request("setBreakpoints", BP);
  console.log(`  [${label}] setBreakpoints -> ${JSON.stringify(bp.body?.breakpoints)}`);
  await c.request("configurationDone"); await p;
  const th = await c.request("threads", {}, 6000);
  console.log(`  [${label}] owns: ${JSON.stringify((th.body?.threads ?? []).map((t) => t.name))}`);
  return c;
}

const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
let cid = 0; const cpend = new Map();
const cdpSend = (m, p = {}, s) => new Promise((res) => { const o = { id: ++cid, method: m, params: p, ...(s ? { sessionId: s } : {}) }; cpend.set(o.id, res); cdp.send(JSON.stringify(o)); });
cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && cpend.has(m.id)) { cpend.get(m.id)(m); cpend.delete(m.id); } });
// attach mode: the extension must already be installed. This is the step a nvim
// command would automate (--load-extension is dead on Chrome 137+).
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
console.log(`[cdp] extension installed: ${extId}`);
await new Promise((r) => setTimeout(r, 1500));

const root = connect("root", reverse);
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
const rootAttach = root.request("attach", { type: "pwa-chrome", request: "attach", name: "pr", port: Number(cdpPort), ...prConfig });
await root.waitFor("initialized", 8000).catch(() => {});
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
const ra = await rootAttach;
console.log(`[dap] attach success: ${ra.success}${ra.success ? "" : " -- " + (ra.message ?? "")}`);
await new Promise((r) => setTimeout(r, 3000));

const { result: { targetId } } = await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId } } = await cdpSend("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 1200));
await cdpSend("Runtime.evaluate", { expression: `setInterval(() => chrome.runtime.sendMessage({type:"retry_save",request:{windowId:1,tabIds:[1],source:"save_all"}}), 600)` }, sessionId);
console.log("[cdp] driving retry_save every 600ms");

const all = () => [root, ...children];
await Promise.race([...all().map((c) => c.waitFor("stopped", 25000)), new Promise((r) => setTimeout(r, 26000))]).catch(() => {});
let hit = false;
for (const c of all()) {
  const s = c.events.find((e) => e.event === "stopped");
  if (!s) continue;
  hit = true;
  console.log(`\n*** STOPPED in ${c.label} ***`);
  const st = await c.request("stackTrace", { threadId: s.body.threadId, levels: 4 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
const owned = [];
for (const c of all()) { const th = await c.request("threads", {}, 5000); for (const t of th.body?.threads ?? []) owned.push(t.name); }
console.log(`\n[result] sessions=${children.length} | worker owned: ${owned.some((n) => /background\.js|service.?worker/i.test(n)) ? "YES" : "NO"} | STOPPED: ${hit ? "YES" : "NO"}`);
console.log(`[result] config passed was ONLY: ${JSON.stringify(prConfig)}`);
process.exit(0);
