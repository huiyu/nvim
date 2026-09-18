// SPIKE: bypass js-debug entirely. Speak CDP to the extension's service worker
// the same way Chrome DevTools does, set a breakpoint, and see whether execution
// actually pauses. This separates "CDP cannot do it" from "js-debug does not".
const [, , cdpPort, extRoot, bundleLine] = process.argv;
setTimeout(() => { console.log("[spike] TIMEOUT"); process.exit(3); }, 60000).unref?.();

const ver = await (await fetch(`http://127.0.0.1:${cdpPort}/json/version`)).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
let id = 0; const pending = new Map(); const handlers = [];
const send = (method, params = {}, sessionId) => new Promise((res) => {
  const m = { id: ++id, method, params, ...(sessionId ? { sessionId } : {}) };
  pending.set(m.id, res); ws.send(JSON.stringify(m));
});
await new Promise((r) => ws.addEventListener("open", r));
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
  for (const h of handlers) h(m);
});

const { result: { id: extId } } = await send("Extensions.loadUnpacked", { path: extRoot });
console.log("[cdp] extension:", extId);
await new Promise((r) => setTimeout(r, 1500));

// Attach to the worker target the way DevTools' "Service Worker" link does.
const { result: { targetInfos } } = await send("Target.getTargets");
const worker = targetInfos.find((t) => t.type === "service_worker" && t.url.includes(extId));
if (!worker) { console.log("no worker target"); process.exit(1); }
console.log("[cdp] worker target:", worker.url.split("/").pop());
const { result: { sessionId: wsId } } = await send("Target.attachToTarget", { targetId: worker.targetId, flatten: true });

let paused = null;
handlers.push((m) => { if (m.method === "Debugger.paused" && m.sessionId === wsId) paused = m.params; });

await send("Debugger.enable", {}, wsId);
const bp = await send("Debugger.setBreakpointByUrl", {
  lineNumber: Number(bundleLine),           // 0-based
  urlRegex: "background\\.js$",
}, wsId);
console.log("[cdp] setBreakpointByUrl ->", JSON.stringify(bp.result ?? bp.error));

// Drive the worker from the extension page, exactly as before.
const { result: { targetId } } = await send("Target.createTarget", { url: `chrome-extension://${extId}/tabs.html` });
const { result: { sessionId: pageId } } = await send("Target.attachToTarget", { targetId, flatten: true });
await new Promise((r) => setTimeout(r, 1200));
send("Runtime.evaluate", {
  expression: `chrome.runtime.sendMessage({type:"retry_save",request:{windowId:1,tabIds:[1],source:"save_all"}})`,
}, pageId);
console.log("[cdp] sent retry_save");

for (let i = 0; i < 100 && !paused; i++) await new Promise((r) => setTimeout(r, 200));
if (!paused) { console.log("*** NOT PAUSED ***"); process.exit(0); }

console.log("*** PAUSED *** reason:", paused.reason);
for (const f of paused.callFrames.slice(0, 3)) {
  console.log(`   ${f.functionName || "(anonymous)"} @ line ${f.location.lineNumber + 1} col ${f.location.columnNumber}`);
}
// Read a local, the way DevTools' scope pane does.
const scope = paused.callFrames[0].scopeChain.find((s) => s.type === "local");
if (scope) {
  const props = await send("Runtime.getProperties", { objectId: scope.object.objectId, ownProperties: true }, wsId);
  const shown = (props.result?.result ?? []).map((p) => `${p.name}=${JSON.stringify(p.value?.value ?? p.value?.description)}`);
  console.log("   locals:", shown.join(", ").slice(0, 160));
}
await send("Debugger.resume", {}, wsId);
console.log("   resumed");
process.exit(0);
