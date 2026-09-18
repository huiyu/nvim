// SPIKE: can CDP Extensions.loadUnpacked install the extension that
// --load-extension no longer installs? Throwaway; no error handling.
const port = process.argv[2], extPath = process.argv[3];
const ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
let id = 0; const pending = new Map();
const send = (method, params = {}, sessionId) => new Promise((res) => {
  const msg = { id: ++id, method, params, ...(sessionId ? { sessionId } : {}) };
  pending.set(msg.id, res); ws.send(JSON.stringify(msg));
});
await new Promise((r) => ws.addEventListener("open", r));
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
console.log("browser:", ver.Browser);
const loaded = await send("Extensions.loadUnpacked", { path: extPath });
console.log("Extensions.loadUnpacked ->", JSON.stringify(loaded.result ?? loaded.error));
const targets = await send("Target.getTargets");
for (const t of targets.result.targetInfos) {
  if (t.url.startsWith("chrome-extension://")) console.log("  target:", t.type, t.url.slice(0, 90));
}
ws.close();
