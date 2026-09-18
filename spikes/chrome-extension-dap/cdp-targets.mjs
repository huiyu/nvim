// SPIKE: after Extensions.loadUnpacked, do the extension's service worker and
// page targets become attachable? Throwaway.
const port = process.argv[2], extPath = process.argv[3];
const ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
let id = 0; const pending = new Map();
const send = (method, params = {}) => new Promise((res) => {
  const msg = { id: ++id, method, params };
  pending.set(msg.id, res); ws.send(JSON.stringify(msg));
});
await new Promise((r) => ws.addEventListener("open", r));
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const { result: { id: extId } } = await send("Extensions.loadUnpacked", { path: extPath });
console.log("extension id:", extId);

const mine = async (label) => {
  const { result } = await send("Target.getTargets");
  const ours = result.targetInfos.filter((t) => t.url.includes(extId));
  console.log(`[${label}] our targets: ${ours.length}`);
  for (const t of ours) console.log("   ", t.type, "|", t.url.replace(`chrome-extension://${extId}`, ""));
  return ours;
};
await sleep(800); await mine("right after install");
// Opening the manager page is what a user does; it should also wake the worker.
await send("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
await sleep(2500); await mine("after opening tabs.html");
ws.close();
