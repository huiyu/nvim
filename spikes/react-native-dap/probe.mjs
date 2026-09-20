// Run from an RN project (or a directory with `npm install ws`).
// node /path/to/probe.mjs http://127.0.0.1:8081 [target-id]
import { createRequire } from 'node:module';
import { once } from 'node:events';
const require = createRequire(`${process.cwd()}/package.json`);
const WebSocket = require('ws');
const base = new URL(process.argv[2] || 'http://127.0.0.1:8081');
const response = await fetch(new URL('/json/list', base), { signal: AbortSignal.timeout(5000) });
if (!response.ok) throw new Error(`Target discovery: HTTP ${response.status}`);
const targets = await response.json();
console.log('Targets:', targets.map(({ id, title, type }) => ({ id, title, type })));
const target = process.argv[3] ? targets.find(t => t.id === process.argv[3]) : targets.length === 1 ? targets[0] : null;
if (!target?.webSocketDebuggerUrl) throw new Error('Choose a target ID; run a development build if the list is empty');
const url = new URL(target.webSocketDebuggerUrl);
const origin = `${url.protocol === 'wss:' ? 'https:' : 'http:'}//${url.host}`;
const ws = new WebSocket(url, { origin, handshakeTimeout: 5000 });
let seq = 0;
const pending = new Map();
let scripts = 0;
ws.on('message', data => {
  const body = JSON.parse(data);
  if (body.method === 'Debugger.scriptParsed') scripts++;
  const item = pending.get(body.id);
  if (!item) return;
  clearTimeout(item.timer);
  pending.delete(body.id);
  if (body.error) item.reject(new Error(JSON.stringify(body.error)));
  else item.resolve(body.result);
});
function request(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++seq;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 5000);
    pending.set(id, { resolve, reject, timer });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
try {
  await once(ws, 'open');
  console.log('Connected with Origin:', origin);
  await request('Runtime.enable');
  await request('Debugger.enable');
  const result = await request('Runtime.evaluate', { expression: '1 + 41', returnByValue: true });
  if (result.result?.value !== 42) throw new Error(`Unexpected evaluation: ${JSON.stringify(result)}`);
  console.log('Runtime evaluation: 42; parsed scripts:', scripts);
  await request('Debugger.disable');
} finally {
  for (const item of pending.values()) clearTimeout(item.timer);
  ws.close();
  const timer = setTimeout(() => ws.terminate(), 1000);
  timer.unref();
}
