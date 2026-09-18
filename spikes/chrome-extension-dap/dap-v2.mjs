// SPIKE v2: correct DAP ordering. js-debug does not answer `attach` until
// configurationDone has run, and a provisional breakpoint is upgraded later
// through a `breakpoint` event - v1 waited on the wrong things.
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot, which] = process.argv;
const TARGETS = {
  worker: { file: `${repoRoot}/apps/extension/entrypoints/background.ts`, line: 21 },
  page:   { file: `${repoRoot}/apps/extension/entrypoints/tabs/main.tsx`,  line: 9 },
};
const { file: BP_FILE, line: BP_LINE } = TARGETS[which];
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 90000).unref?.();

const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
let cdpId = 0; const cdpPending = new Map();
const cdpSend = (method, params = {}, sessionId) => new Promise((res) => {
  const m = { id: ++cdpId, method, params, ...(sessionId ? { sessionId } : {}) };
  cdpPending.set(m.id, res); cdp.send(JSON.stringify(m));
});
cdp.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && cdpPending.has(m.id)) { cdpPending.get(m.id)(m); cdpPending.delete(m.id); }
});

const sock = net.connect(Number(dapPort), "127.0.0.1");
await new Promise((r) => sock.once("connect", r));
let seq = 0; const pending = new Map(); const events = []; const listeners = [];
const request = (command, args = {}, ms = 30000) => new Promise((res) => {
  const msg = { seq: ++seq, type: "request", command, arguments: args };
  const t = setTimeout(() => res({ success: false, message: "timeout" }), ms);
  pending.set(msg.seq, (r) => { clearTimeout(t); res(r); });
  const body = JSON.stringify(msg);
  sock.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
});
const waitFor = (event, ms) => new Promise((res, rej) => {
  const hit = events.find((e) => e.event === event);
  if (hit) return res(hit);
  const t = setTimeout(() => rej(new Error(`timeout waiting for ${event}`)), ms);
  listeners.push({ event, res: (e) => { clearTimeout(t); res(e); } });
});
let buf = Buffer.alloc(0);
sock.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  for (;;) {
    const sep = buf.indexOf("\r\n\r\n"); if (sep < 0) break;
    const len = Number(/Content-Length: (\d+)/i.exec(buf.subarray(0, sep).toString())?.[1]);
    if (buf.length < sep + 4 + len) break;
    const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString());
    buf = buf.subarray(sep + 4 + len);
    if (msg.type === "response" && pending.has(msg.request_seq)) { pending.get(msg.request_seq)(msg); pending.delete(msg.request_seq); }
    else if (msg.type === "event") {
      events.push(msg);
      if (msg.event === "breakpoint") console.log("[event] breakpoint ->", JSON.stringify(msg.body?.breakpoint));
      else if (["stopped", "terminated"].includes(msg.event)) console.log("[event]", msg.event, JSON.stringify(msg.body ?? {}).slice(0, 150));
      for (let i = listeners.length - 1; i >= 0; i--)
        if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
    }
  }
});

await request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true });
// Do NOT await: js-debug answers this only after configurationDone.
const attachPromise = request("attach", {
  type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort),
  webRoot: `${repoRoot}/apps/extension`, sourceMaps: true, targetSelection: "automatic",
  // js-debug's default target filter ignores the chrome-extension: origin;
  // open it up explicitly and let sourcemaps resolve from anywhere.
  urlFilter: "chrome-extension://*",
  resolveSourceMapLocations: null,
  sourceMapPathOverrides: { "chrome-extension://*/*": `${repoRoot}/apps/extension/*` },
});
await waitFor("initialized", 10000).catch((e) => console.log("[dap]", e.message));
const bp = await request("setBreakpoints", { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] });
console.log("[dap] setBreakpoints (initial) ->", JSON.stringify(bp.body?.breakpoints));
await request("configurationDone");
const attach = await attachPromise;
console.log("[dap] attach success:", attach.success, attach.message ?? "");

// Install the extension only now, so the worker starts under the debugger.
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
console.log("[cdp] extension installed:", extId);
if (which === "page") {
  await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
}
const th = await request("threads", {}, 8000);
console.log("[dap] threads js-debug owns:", JSON.stringify(th.body?.threads ?? th.message));
try {
  const stopped = await waitFor("stopped", 25000);
  console.log("[dap] *** STOPPED ***", JSON.stringify(stopped.body));
  const st = await request("stackTrace", { threadId: stopped.body.threadId, levels: 3 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
} catch (e) { console.log("[dap]", e.message); }
const disk = events.filter((e) => e.event === "loadedSource").map((e) => e.body?.source?.path)
  .filter((p) => p && p.startsWith("/") && /\.tsx?$/.test(p));
console.log("[dap] on-disk TS sources resolved:", disk.length);
disk.slice(0, 5).forEach((p) => console.log("   ", p));
process.exit(0);
