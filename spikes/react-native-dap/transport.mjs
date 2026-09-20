// Actual RN middleware, with a synthetic device on its app-facing socket.
// This measures the transport and Origin check, not Hermes or source maps.
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const require = createRequire(`${process.cwd()}/package.json`);
const { createDevMiddleware } = require('@react-native/dev-middleware');
const { WebSocket } = require('ws');
const server = http.createServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const { middleware, websocketEndpoints } = createDevMiddleware({
  projectRoot: process.cwd(), serverBaseUrl: base,
});
server.on('request', (req, res) => middleware(req, res, () => { res.writeHead(404); res.end(); }));
server.on('upgrade', (req, socket, head) => {
  const wss = websocketEndpoints[new URL(req.url, base).pathname];
  if (!wss) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, req));
});
const device = new WebSocket(`${base.replace('http:', 'ws:')}/inspector/device?device=fixture&name=fixture&app=fixture`);
device.on('message', data => {
  const event = JSON.parse(data);
  if (event.event === 'getPages') device.send(JSON.stringify({ event: 'getPages', payload: [
    { id: '1', title: 'Synthetic transport fixture', app: 'fixture', capabilities: { nativePageReloads: true, nativeSourceCodeFetching: true } },
  ] }));
  if (event.event === 'wrappedEvent') {
    const message = JSON.parse(event.payload.wrappedEvent);
    if (!message.id) return;
    const result = message.method === 'Runtime.evaluate' ? { result: { type: 'number', value: 42 } } : {};
    device.send(JSON.stringify({ event: 'wrappedEvent', payload: {
      pageId: '1', wrappedEvent: JSON.stringify({ id: message.id, result }),
    } }));
  }
});
try {
  await once(device, 'open');
  let targets = [];
  for (let i = 0; i < 30 && !targets.length; i++) {
    await new Promise(resolve => setTimeout(resolve, 100));
    targets = await (await fetch(`${base}/json/list`)).json();
  }
  assert.equal(targets.length, 1);
  console.log('/json/list exposes the synthetic device');
  const withoutOrigin = new WebSocket(targets[0].webSocketDebuggerUrl);
  const [error] = await once(withoutOrigin, 'error');
  assert.match(error.message, /401/);
  console.log('No Origin: HTTP 401 (expected)');
  const child = spawn(process.execPath, [fileURLToPath(new URL('./probe.mjs', import.meta.url)), base, targets[0].id], { stdio: 'inherit' });
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
  console.log('PASS: RN inspector transport accepts an external client with Origin');
} finally {
  device.terminate();
  for (const wss of Object.values(websocketEndpoints)) {
    for (const client of wss.clients) client.terminate();
    wss.close();
  }
  server.closeAllConnections();
  server.close();
}
// InspectorProxy owns background heartbeat timers; the isolated harness is done.
process.exit(0);
