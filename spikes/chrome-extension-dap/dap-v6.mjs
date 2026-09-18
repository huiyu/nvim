// SPIKE v6: run WITH the vite dev server alive - v4/v5 had killed it, so the
// page only ever loaded an empty HTML shell and no breakpoint could bind.
//
// The two surfaces need OPPOSITE path config, which is the real finding:
//   page   -> code is served from http://localhost:3000/<path relative to apps/extension>
//   worker -> code is bundled into chrome-extension://<id>/background.js with an inline map
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot, mode] = process.argv;
const EXT_APP = `${repoRoot}/apps/extension`;
const SUBJECT = {
  page:   { file: `${EXT_APP}/entrypoints/tabs/main.tsx`, line: 9 },
  worker: { file: `${EXT_APP}/src/features/save-all/save-request.ts`, line: 11 },
}[mode];
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 95000).unref?.();

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
        if (msg.event === "breakpoint" && msg.body?.breakpoint?.verified) console.log(`[${label}] VERIFIED ->`, JSON.stringify(msg.body.breakpoint));
        for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      } } });
  return api;
}

const tuning = mode === "page"
  ? { webRoot: EXT_APP, sourceMaps: true, resolveSourceMapLocations: null,
      // js-debug's default outFiles interpolates ${workspaceFolder}; with none
      // set it matches nothing and every script is filtered out before parsing.
      __workspaceFolder: repoRoot, outFiles: [`${repoRoot}/**/*`, "!**/node_modules/**"] }
  : { webRoot: EXT_APP, sourceMaps: true, resolveSourceMapLocations: null,
      __workspaceFolder: repoRoot, outFiles: [`${extRoot}/**/*.js`],
      sourceMapPathOverrides: { "chrome-extension://*/*": `${EXT_APP}/*` } };

const children = [];
const BP = { source: { path: SUBJECT.file }, breakpoints: [{ line: SUBJECT.line }] };
async function startChild(config) {
  const label = `child${children.length + 1}`;
  const c = connect(label, (req, api) => { if (req.command === "startDebugging") { api.respond(req); startChild(req.arguments.configuration); } });
  children.push(c); await c.ready;
  await c.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = c.request("attach", { ...config, ...tuning });
  await c.waitFor("initialized", 8000).catch(() => {});
  const bp = await c.request("setBreakpoints", BP);
  console.log(`[${label}] setBreakpoints ->`, JSON.stringify(bp.body?.breakpoints));
  await c.request("configurationDone"); await p;
  const th = await c.request("threads", {}, 6000);
  console.log(`[${label}] threads:`, JSON.stringify(th.body?.threads ?? []));
  return c;
}

const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
let cid = 0; const cpend = new Map();
const cdpSend = (m, p = {}, s) => new Promise((res) => { const o = { id: ++cid, method: m, params: p, ...(s ? { sessionId: s } : {}) }; cpend.set(o.id, res); cdp.send(JSON.stringify(o)); });
cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && cpend.has(m.id)) { cpend.get(m.id)(m); cpend.delete(m.id); } });
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
console.log("[cdp] extension:", extId);
const { result: { targetId } } = await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId } } = await cdpSend("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 2500));
// Prove the page actually got its code this time.
const probe = await cdpSend("Runtime.evaluate", { expression: "document.getElementById('root')?.childElementCount ?? -1", returnByValue: true }, sessionId);
console.log("[cdp] react mounted children in #root:", JSON.stringify(probe.result?.result?.value));

const root = connect("root", (req, api) => { if (req.command === "startDebugging") { api.respond(req); startChild(req.arguments.configuration); } });
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
const rootAttach = root.request("attach", { type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort), targetSelection: "automatic", ...tuning });
await root.waitFor("initialized", 8000).catch(() => {});
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
console.log("[root] attach success:", (await rootAttach).success);
await new Promise((r) => setTimeout(r, 2500));

if (mode === "page") {
  console.log("[cdp] reloading page ...");
  await cdpSend("Page.enable", {}, sessionId);
  await cdpSend("Page.reload", { ignoreCache: true }, sessionId);
} else {
  console.log("[cdp] driving retry_save every 700ms ...");
  await cdpSend("Runtime.evaluate", { expression: `setInterval(() => chrome.runtime.sendMessage({type:"retry_save",request:{windowId:1,tabIds:[1],source:"save_all"}}), 700)` }, sessionId);
}

const all = () => [root, ...children];
await Promise.race([...all().map((c) => c.waitFor("stopped", 25000)), new Promise((r) => setTimeout(r, 26000))]).catch(() => {});
let hit = false;
for (const c of all()) {
  const s = c.events.find((e) => e.event === "stopped");
  if (!s) continue;
  hit = true;
  console.log(`[${c.label}] *** STOPPED *** ${JSON.stringify(s.body)}`);
  const st = await c.request("stackTrace", { threadId: s.body.threadId, levels: 4 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
for (const c of all()) {
  const ls = await c.request("loadedSources", {}, 8000);
  const srcs = (ls.body?.sources ?? []).map((x) => x.path || x.name);
  const ts = srcs.filter((p) => /\.tsx?$/.test(p));
  console.log(`[${c.label}] loadedSources: ${srcs.length} (ts/tsx: ${ts.length})`);
  ts.slice(0, 5).forEach((p) => console.log("     ", p));
}
console.log(`[spike] mode=${mode} stopped:`, hit ? "YES" : "NO");
process.exit(0);
