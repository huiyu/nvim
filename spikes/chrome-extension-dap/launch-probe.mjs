// SPIKE round 6: LAUNCH mode. The debugger starts the browser and installs the
// extension itself -- no pre-started Chrome, no manual load. This is what the
// upstream PR intends but cannot do on Chrome 137+, which ignores
// --load-extension; this fork installs over CDP instead.
import net from "node:net";
const [, , dapPort, extRoot, repoRoot, userDataDir] = process.argv;
const BP_FILE = `${repoRoot}/apps/extension/entrypoints/background.ts`;
const BP_LINE = 21;  // chrome.action.onClicked.addListener -- runs on every worker startup
setTimeout(() => { console.log("[spike] TIMEOUT"); process.exit(3); }, 90000).unref?.();

function connect(label, onReverse) {
  const sock = net.connect(Number(dapPort), "127.0.0.1");
  let seq = 0, buf = Buffer.alloc(0);
  const pending = new Map(), listeners = [], events = [];
  const send = (o) => { const b = JSON.stringify(o); sock.write(`Content-Length: ${Buffer.byteLength(b)}\r\n\r\n${b}`); };
  const api = { label, events,
    ready: new Promise((r) => sock.once("connect", r)),
    request: (command, args = {}, ms = 40000) => new Promise((res) => {
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
        if (msg.event === "output" && msg.body?.category !== "telemetry") {
          const o = String(msg.body?.output ?? "").trim();
          if (o && !o.startsWith("js-debug/")) console.log(`  [${label}] ${msg.body.category}: ${o.slice(0, 140)}`);
        }
        for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
      } } });
  return api;
}

const children = [];
const BP = { source: { path: BP_FILE }, breakpoints: [{ line: BP_LINE }] };
const reverse = (req, api) => { api.respond(req); if (req.command === "startDebugging") startChild(req.arguments.configuration); };
async function startChild(config) {
  const label = `child${children.length + 1}`;
  const c = connect(label, reverse);
  children.push(c); await c.ready;
  await c.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
  const p = c.request("attach", config);
  await c.waitFor("initialized", 10000).catch(() => {});
  await c.request("setBreakpoints", BP);
  await c.request("configurationDone"); await p;
  const th = await c.request("threads", {}, 8000);
  console.log(`  [${label}] owns: ${JSON.stringify((th.body?.threads ?? []).map((t) => t.name))}`);
  return c;
}

const root = connect("root", reverse);
await root.ready;
await root.request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true, supportsStartDebuggingRequest: true });
// LAUNCH: the only paths given are the extension and a profile dir.
const launchArgs = {
  type: "pwa-chrome", request: "launch", name: "launch-probe",
  extensionPath: extRoot,
  userDataDir,
  runtimeExecutable: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  runtimeArgs: ["--headless=new", "--no-first-run", "--no-default-browser-check"],
};
console.log("[dap] launch with:", JSON.stringify({ extensionPath: extRoot, userDataDir }));
const launching = root.request("launch", launchArgs);
await root.waitFor("initialized", 15000).catch(() => console.log("  (no initialized event)"));
await root.request("setBreakpoints", BP);
await root.request("configurationDone");
const lr = await launching;
console.log(`[dap] launch success: ${lr.success}${lr.success ? "" : " -- " + (lr.message ?? "")}`);

const all = () => [root, ...children];
await Promise.race([...all().map((c) => c.waitFor("stopped", 30000)), new Promise((r) => setTimeout(r, 31000))]).catch(() => {});
let hit = false;
for (const c of all()) {
  const s = c.events.find((e) => e.event === "stopped");
  if (!s) continue;
  hit = true;
  console.log(`\n*** STOPPED in ${c.label} ***`);
  const st = await c.request("stackTrace", { threadId: s.body.threadId, levels: 3 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   ${f.name} @ ${f.source?.path ?? f.source?.name}:${f.line}`);
}
const owned = [];
for (const c of all()) { const th = await c.request("threads", {}, 5000); for (const t of th.body?.threads ?? []) owned.push(t.name); }
console.log(`\n[result] worker owned: ${owned.some((n) => /background\.js|service.?worker/i.test(n)) ? "YES" : "NO"} | STOPPED: ${hit ? "YES" : "NO"}`);
console.log(`[result] owned: ${JSON.stringify(owned)}`);
await root.request("disconnect", { terminateDebuggee: true }, 5000).catch(() => {});
process.exit(0);
