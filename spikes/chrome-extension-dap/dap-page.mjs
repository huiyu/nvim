// SPIKE (control): debug only the extension PAGE, not the service worker.
// The CDP socket is closed before js-debug attaches, so a second CDP client
// cannot be blamed for the session errors seen in the worker run.
import net from "node:net";
const [, , dapPort, cdpPort, extRoot, repoRoot] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/entrypoints/tabs/main.tsx`;
const BP_LINE = 9;
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 70000).unref?.();

// 1. Install the extension, then drop the CDP connection entirely.
const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const cdp = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => cdp.addEventListener("open", r));
const extId = await new Promise((res) => {
  cdp.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id === 1) res(m.result.id); });
  cdp.send(JSON.stringify({ id: 1, method: "Extensions.loadUnpacked", params: { path: extRoot } }));
});
cdp.close();
console.log("[cdp] extension id:", extId, "(cdp socket closed)");

// 2. js-debug attaches with no other CDP client present.
const sock = net.connect(Number(dapPort), "127.0.0.1");
await new Promise((r) => sock.once("connect", r));
let seq = 0; const pending = new Map(); const events = []; const listeners = [];
const request = (command, args = {}, ms = 25000) => new Promise((res) => {
  const msg = { seq: ++seq, type: "request", command, arguments: args };
  const t = setTimeout(() => { console.log(`[dap] ${command} TIMED OUT`); res({ success: false, message: "timeout" }); }, ms);
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
      if (msg.event === "output" && /error/.test(String(msg.body?.output ?? "")))
        console.log("[event] error:", JSON.stringify(msg.body?.data ?? {}).slice(0, 300));
      else if (["terminated", "exited", "stopped", "initialized"].includes(msg.event))
        console.log("[event]", msg.event, JSON.stringify(msg.body ?? {}).slice(0, 160));
      for (let i = listeners.length - 1; i >= 0; i--)
        if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
    }
  }
});

await request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true });
const attach = await request("attach", {
  type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort),
  webRoot: `${repoRoot}/apps/extension`,
  urlFilter: `chrome-extension://${extId}/*`,
  sourceMapPathOverrides: { [`chrome-extension://${extId}/*`]: `${repoRoot}/apps/extension/*` },
  sourceMaps: true, targetSelection: "automatic",
});
console.log("[dap] attach success:", attach.success);
await waitFor("initialized", 8000).catch((e) => console.log("[dap]", e.message));
const bp = await request("setBreakpoints", { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] });
console.log("[dap] setBreakpoints ->", JSON.stringify(bp.body?.breakpoints ?? bp.message));
await request("configurationDone");

// 3. Open the page over the HTTP endpoint - still no second CDP client.
await fetch(`http://127.0.0.1:${cdpPort}/json/new?chrome-extension://${extId}/tabs.html`, { method: "PUT" })
  .then((r) => r.text()).then((t) => console.log("[http] opened page:", t.slice(0, 80)))
  .catch((e) => console.log("[http] open failed:", e.message));

try {
  const stopped = await waitFor("stopped", 20000);
  console.log("[dap] *** STOPPED ***", JSON.stringify(stopped.body));
  const st = await request("stackTrace", { threadId: stopped.body.threadId, levels: 3 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
} catch (e) { console.log("[dap]", e.message); }
const seen = events.filter((e) => e.event === "loadedSource").map((e) => e.body?.source?.path).filter(Boolean);
console.log("[dap] loadedSource total:", seen.length);
console.log("[dap] on-disk .ts/.tsx sources js-debug resolved:", JSON.stringify(seen.filter((p) => p.startsWith("/") && /\.tsx?$/.test(p)).slice(0, 8), null, 1));
process.exit(0);
