// SPIKE (control 2): same attach config against a Chrome with NO extension.
// If this succeeds, the failure above is attributable to the extension's
// service worker, not to a malformed attach request.
import net from "node:net";
const [, , dapPort, cdpPort] = process.argv;
setTimeout(() => { console.log("[spike] GLOBAL TIMEOUT"); process.exit(3); }, 45000).unref?.();
const sock = net.connect(Number(dapPort), "127.0.0.1");
await new Promise((r) => sock.once("connect", r));
let seq = 0; const pending = new Map();
const request = (command, args = {}, ms = 25000) => new Promise((res) => {
  const msg = { seq: ++seq, type: "request", command, arguments: args };
  const t = setTimeout(() => res({ success: false, message: "timeout" }), ms);
  pending.set(msg.seq, (r) => { clearTimeout(t); res(r); });
  const body = JSON.stringify(msg);
  sock.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
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
    else if (msg.type === "event" && msg.event === "output" && /error/.test(String(msg.body?.output ?? "")))
      console.log("[event] error:", JSON.stringify(msg.body?.data ?? {}).slice(0, 200));
  }
});
await request("initialize", { clientID: "spike", adapterID: "pwa-chrome", linesStartAt1: true, columnsStartAt1: true, pathFormat: "path", supportsConfigurationDoneRequest: true });
const attach = await request("attach", { type: "pwa-chrome", request: "attach", name: "spike", port: Number(cdpPort), webRoot: "/tmp", sourceMaps: true });
console.log("[dap] PLAIN attach success:", attach.success, attach.message ?? "");
process.exit(0);
