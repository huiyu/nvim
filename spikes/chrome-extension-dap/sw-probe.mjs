// SPIKE: can js-debug be made to take over the extension's SERVICE WORKER?
// Its bundle carries a full serviceWorkerModel (ServiceWorker.enable/stopWorker,
// workerVersionUpdated) and `Du` includes "service_worker" -- the worker is only
// kept out by the attach-mode target filter:
//   wa = r => e => e.type === "page" && ... && r(e)
//   if (t.targetSelection !== "pick") return i;
// Arg 5 selects targetSelection so "pick" can be compared against "automatic".
// Arg 6 optionally points at a patched adapter's port (the caller starts it).
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot, targetSelection] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/src/features/save-all/save-request.ts`;
const BP_LINE = 11;
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
        if (msg.event === "breakpoint" && msg.body?.breakpoint?.verified) console.log(`  [${label}] BREAKPOINT VERIFIED`);
        for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      } } });
  return api;
}

let tuning;
const buildTuning = (extId) => ({
  // webRoot is the base the extension's URLs map onto, and the map's relative
  // sources ("../../src/x.ts") resolve from THERE -- so it must be the build
  // output directory, not the package root. With the package root, ../../ walks
  // two levels above it and lands outside the workspace.
  webRoot: extRoot, sourceMaps: true,
  resolveSourceMapLocations: null,
  // One wildcard on each side. "chrome-extension://*/*" would capture the id
  // too, and js-debug has no way to say "use the second capture".
  sourceMapPathOverrides: { [`chrome-extension://${extId}/*`]: `${repoRoot}/apps/extension/*` },
});
const children = [];
const BP = { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] };
// Any reverse request must be answered or js-debug stalls; startDebugging also
// spawns the child session that actually owns a target.
const reverse = (req, api) => {
  if (req.command !== "startDebugging") console.log(`  [${api.label}] reverse request: ${req.command}`);
  api.respond(req);
  if (req.command === "startDebugging") startChild(req.arguments.configuration);
};
async function startChild(config) {
  const label = `child${children.length + 1}`;
  const c = connect(label, reverse);
  children.push(c); await c.ready;
  await c.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = c.request("attach", { ...config, ...tuning });
  await c.waitFor("initialized", 8000).catch(() => {});
  await c.request("setBreakpoints", BP);
  await c.request("configurationDone"); await p;
  const th = await c.request("threads", {}, 6000);
  const names = (th.body?.threads ?? []).map((t) => t.name);
  console.log(`  [${label}] owns: ${JSON.stringify(names)}`);
  return c;
}

const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
let cid = 0; const cpend = new Map();
const cdpSend = (m, p = {}, s) => new Promise((res) => { const o = { id: ++cid, method: m, params: p, ...(s ? { sessionId: s } : {}) }; cpend.set(o.id, res); cdp.send(JSON.stringify(o)); });
cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && cpend.has(m.id)) { cpend.get(m.id)(m); cpend.delete(m.id); } });
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
tuning = buildTuning(extId);
console.log(`[cfg] sourceMapPathOverrides: chrome-extension://${extId}/* -> ${repoRoot}/apps/extension/*`);
await new Promise((r) => setTimeout(r, 1200));
const { result: { targetInfos } } = await cdpSend("Target.getTargets");
console.log(`[cdp] extension ${extId}; targets Chrome exposes:`);
for (const t of targetInfos.filter((t) => t.url.includes(extId))) console.log(`  ${t.type}  ${t.url.replace(`chrome-extension://${extId}`, "")}`);

const root = connect("root", reverse);
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
const rootAttach = root.request("attach", { type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort), targetSelection, ...tuning });
await root.waitFor("initialized", 8000).catch(() => {});
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
console.log(`[dap] attach(targetSelection=${targetSelection}) success: ${(await rootAttach).success}`);
await new Promise((r) => setTimeout(r, 2500));

// Drive parseSaveRequest from the extension page. The page needs no dev server
// for this: chrome.runtime exists on the page regardless of whether React ran.
const { result: { targetId } } = await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId } } = await cdpSend("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 1200));
console.log("[cdp] driving retry_save every 600ms");
await cdpSend("Runtime.evaluate", { expression: `setInterval(() => chrome.runtime.sendMessage({type:"retry_save",request:{windowId:1,tabIds:[1],source:"save_all"}}), 600)` }, sessionId);

const all = () => [root, ...children];
await Promise.race([...all().map((c) => c.waitFor("stopped", 22000)), new Promise((r) => setTimeout(r, 23000))]).catch(() => {});
let hit = false;
for (const c of all()) {
  const s = c.events.find((e) => e.event === "stopped");
  if (!s) continue;
  hit = true;
  console.log(`[dap] *** STOPPED in ${c.label} ***`);
  const st = await c.request("stackTrace", { threadId: s.body.threadId, levels: 4 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
const owned = [];
for (const c of all()) {
  const th = await c.request("threads", {}, 5000);
  const names = (th.body?.threads ?? []).map((t) => t.name);
  for (const n of names) owned.push(n);
  // Only the session that owns OUR worker is interesting: what did js-debug
  // resolve its sources to, and did the breakpoint bind?
  if (names.some((n) => n.includes(extId))) {
    const ls = await c.request("loadedSources", {}, 8000);
    const srcs = (ls.body?.sources ?? []).map((x) => x.path || x.name);
    console.log(`[diag] ${c.label} owns OUR worker; loadedSources=${srcs.length}`);
    const target = srcs.filter((x) => /save-request|save-all/.test(x));
    console.log(`[diag] sources matching save-request/save-all: ${JSON.stringify(target, null, 1)}`);
    console.log(`[diag] breakpoint path we ask for: ${BP_FILE}`);
    console.log(`[diag] exact match present: ${srcs.includes(BP_FILE)}`);
    const bp = await c.request("setBreakpoints", BP);
    console.log(`[diag] re-set breakpoint -> ${JSON.stringify(bp.body?.breakpoints)}`);
  }
}
console.log(`[result] targetSelection=${targetSelection} | sessions=${children.length} | js-debug owns: ${JSON.stringify(owned)}`);
console.log(`[result] service worker owned: ${owned.some((n) => /background\.js|service.?worker/i.test(n)) ? "YES" : "NO"} | stopped: ${hit ? "YES" : "NO"}`);
process.exit(0);
