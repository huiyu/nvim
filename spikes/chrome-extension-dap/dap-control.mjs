// SPIKE (positive control): a plain http page with a plain .js file.
// If THIS does not stop, the client is at fault, not the extension.
import net from "node:net";
const [, , dapPort, cdpPort, webRoot, url] = process.argv;
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 60000).unref?.();
const sock = net.connect(Number(dapPort), "127.0.0.1");
await new Promise((r) => sock.once("connect", r));
let seq = 0; const pending = new Map(); const events = []; const listeners = [];
const request = (c, a = {}, ms = 30000) => new Promise((res) => {
  const m = { seq: ++seq, type: "request", command: c, arguments: a };
  const t = setTimeout(() => res({ success: false, message: "timeout" }), ms);
  pending.set(m.seq, (r) => { clearTimeout(t); res(r); });
  const b = JSON.stringify(m); sock.write(`Content-Length: ${Buffer.byteLength(b)}\r\n\r\n${b}`);
});
const waitFor = (ev, ms) => new Promise((res, rej) => {
  const hit = events.find((e) => e.event === ev); if (hit) return res(hit);
  const t = setTimeout(() => rej(new Error(`timeout waiting for ${ev}`)), ms);
  listeners.push({ event: ev, res: (e) => { clearTimeout(t); res(e); } });
});
let buf = Buffer.alloc(0);
sock.on("data", (chunk) => { buf = Buffer.concat([buf, chunk]);
  for (;;) { const sep = buf.indexOf("\r\n\r\n"); if (sep < 0) break;
    const len = Number(/Content-Length: (\d+)/i.exec(buf.subarray(0, sep).toString())?.[1]);
    if (buf.length < sep + 4 + len) break;
    const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString()); buf = buf.subarray(sep + 4 + len);
    if (msg.type === "response" && pending.has(msg.request_seq)) { pending.get(msg.request_seq)(msg); pending.delete(msg.request_seq); }
    else if (msg.type === "event") { events.push(msg);
      if (msg.event === "breakpoint") console.log("[event] breakpoint ->", JSON.stringify(msg.body?.breakpoint));
      for (let i = listeners.length - 1; i >= 0; i--) if (listeners[i].event === msg.event) { listeners[i].res(msg); listeners.splice(i, 1); }
    } } });
await request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true });
const attachP = request("attach", { type: "pwa-chrome", request: "attach", name: "ctl", port: Number(cdpPort), webRoot, sourceMaps: true, targetSelection: "automatic" });
await waitFor("initialized", 10000).catch((e) => console.log("[dap]", e.message));
const bp = await request("setBreakpoints", { source: { path: `${webRoot}/app.js` }, breakpoints: [{ line: 2 }] });
console.log("[dap] setBreakpoints ->", JSON.stringify(bp.body?.breakpoints));
await request("configurationDone");
console.log("[dap] attach success:", (await attachP).success);
await fetch(`http://127.0.0.1:${cdpPort}/json/new?${url}`, { method: "PUT" }).catch(() => {});
const th = await request("threads", {}, 8000);
console.log("[dap] threads:", JSON.stringify(th.body?.threads ?? []));
try { const s = await waitFor("stopped", 20000);
  console.log("[dap] *** STOPPED ***", JSON.stringify(s.body));
  const st = await request("stackTrace", { threadId: s.body.threadId, levels: 2 });
  for (const f of st.body?.stackFrames ?? []) console.log(`   frame: ${f.name} @ ${f.source?.path}:${f.line}`);
} catch (e) { console.log("[dap]", e.message); }
process.exit(0);
