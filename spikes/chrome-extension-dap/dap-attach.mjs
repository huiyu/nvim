// SPIKE: drive js-debug over raw DAP the way nvim-dap would, and see whether a
// breakpoint set on a real .ts path binds and hits inside the extension's
// service worker. Throwaway: no retries, no cleanup, happy path only.
import net from "node:net";

const DEADLINE = setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 75000);
DEADLINE.unref?.();
const step = (m) => console.log("[step]", m);

const [, , dapPort, cdpPort, extRoot, repoRoot] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/src/features/save-all/save-request.ts`;
const BP_LINE = 11;

// --- CDP side: install the extension, then drive the page that triggers code.
const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
let cdpId = 0; const cdpPending = new Map();
const cdpSend = (method, params = {}, sessionId) => new Promise((res) => {
  const m = { id: ++cdpId, method, params, ...(sessionId ? { sessionId } : {}) };
  cdpPending.set(m.id, res); cdp.send(JSON.stringify(m));
});
await new Promise((r) => cdp.addEventListener("open", r));
cdp.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && cdpPending.has(m.id)) { cdpPending.get(m.id)(m); cdpPending.delete(m.id); }
});
const { result: { id: extId } } = await cdpSend("Extensions.loadUnpacked", { path: extRoot });
console.log("[cdp] extension id:", extId);

// --- DAP side: speak the protocol js-debug expects over TCP.
const sock = net.connect(Number(dapPort), "127.0.0.1");
await new Promise((r) => sock.once("connect", r));
let seq = 0; const dapPending = new Map(); const events = [];
const waitFor = (event, ms = 15000) => new Promise((res, rej) => {
  const hit = events.find((e) => e.event === event);
  if (hit) return res(hit);
  const t = setTimeout(() => rej(new Error(`timeout waiting for ${event}`)), ms);
  listeners.push({ event, res: (e) => { clearTimeout(t); res(e); } });
});
const listeners = [];
const request = (command, args = {}, ms = 20000) => new Promise((res) => {
  const msg = { seq: ++seq, type: "request", command, arguments: args };
  const t = setTimeout(() => { console.log(`[dap] ${command} TIMED OUT`); res({ success: false, message: "timeout" }); }, ms);
  dapPending.set(msg.seq, (r) => { clearTimeout(t); res(r); });
  const body = JSON.stringify(msg);
  sock.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
});
let buf = Buffer.alloc(0);
sock.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  for (;;) {
    const sep = buf.indexOf("\r\n\r\n");
    if (sep < 0) break;
    const len = Number(/Content-Length: (\d+)/i.exec(buf.subarray(0, sep).toString())?.[1]);
    if (buf.length < sep + 4 + len) break;
    const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString());
    buf = buf.subarray(sep + 4 + len);
    if (msg.type === "response" && dapPending.has(msg.request_seq)) {
      dapPending.get(msg.request_seq)(msg); dapPending.delete(msg.request_seq);
    } else if (msg.type === "event") {
      events.push(msg);
      if (msg.event === "output" && /error|browserVersion|launch/.test(String(msg.body?.output ?? ""))) {
        console.log("[event] output", String(msg.body?.output).trim(), "\n    data:", JSON.stringify(msg.body?.data ?? {}).slice(0, 700));
      } else if (["terminated","exited","stopped","initialized","thread"].includes(msg.event)) {
        console.log("[event]", msg.event, JSON.stringify(msg.body ?? {}).slice(0, 200));
      }
      for (let i = listeners.length - 1; i >= 0; i--) {
        if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      }
    }
  }
});

step("initialize");
await request("initialize", {
  clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true,
  pathFormat: "path", supportsConfigurationDoneRequest: true, supportsVariableType: true,
});
step("attach");
const attach = await request("attach", {
  type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort),
  webRoot: `${repoRoot}/apps/extension`,
  // Extension code lives under chrome-extension://; without this the relative
  // sourcemap paths normalise against that origin and never reach disk.
  sourceMapPathOverrides: { "chrome-extension://*/*": `${repoRoot}/apps/extension/*` },
  targetSelection: "automatic", sourceMaps: true,
});
console.log("[dap] attach success:", attach.success, attach.success ? "" : JSON.stringify(attach.body ?? attach.message));
await waitFor("initialized").catch((e) => console.log("[dap]", e.message));

step("setBreakpoints");
const bp = await request("setBreakpoints", {
  source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }],
});
console.log("[dap] setBreakpoints ->", JSON.stringify(bp.body?.breakpoints ?? bp.message));
step("configurationDone");
await request("configurationDone");

// Wake the worker through the manager page, then send the message that reaches
// parseSaveRequest.
const { result: { targetId } } = await cdpSend("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId } } = await cdpSend("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 2000));
cdpSend("Runtime.evaluate", {
  expression: `chrome.runtime.sendMessage({type:"retry_save",request:{windowId:1,tabIds:[1],source:"save_all"}})`,
  awaitPromise: false,
}, sessionId);

try {
  const stopped = await waitFor("stopped", 12000);
  console.log("[dap] STOPPED:", JSON.stringify(stopped.body));
  const st = await request("stackTrace", { threadId: stopped.body.threadId, levels: 3 });
  for (const f of st.body?.stackFrames ?? []) {
    console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
  }
} catch (e) {
  console.log("[dap]", e.message);
}
const sources = events.filter((e) => e.event === "loadedSource")
  .map((e) => e.body?.source?.path).filter((p) => p && p.includes("save-request"));
console.log("[dap] loadedSource paths matching save-request:", JSON.stringify(sources));
process.exit(0);
