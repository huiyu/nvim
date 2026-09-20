# React Native DAP feasibility spike (#19)

The transport is reachable by external clients. This does **not** yet establish
working Hermes source breakpoints through js-debug, and no RN adapter is enabled
in the configuration.

## What was verified

On 2026-09-19, `transport.mjs` ran against the actual
`@react-native/dev-middleware@0.87.1` package with a **synthetic device**, not a
running React Native/Hermes application:

- `/json/list` returned the device's inspector target.
- Connecting without an Origin header failed with HTTP 401.
- The same client with `Origin: http://<inspector-host>:<port>` connected.
- Runtime/Debugger requests and a synthetic evaluation reply traversed the proxy.

Thus the issue's premise that the inspector proxy was removed and external
clients categorically cannot connect is incorrect for this version. The harness
proves discovery, handshake, and message routing only. It does not measure
Hermes breakpoint binding, source maps, pause/resume, or DevTools coexistence.

Sources checked:

- [React Native inspector implementation](https://github.com/react/react-native/blob/main/packages/dev-middleware/src/inspector-proxy/InspectorProxy.js)
  retains `/json/list` and `/inspector/debug`, with Origin validation.
- [vscode-react-native #2781](https://github.com/microsoft/vscode-react-native/issues/2781)
  is a **bug report**, not a PR re-exposing an endpoint. It reports attach/binding
  failures on RN 0.85/0.86.
- [PR #2782](https://github.com/microsoft/vscode-react-native/pull/2782), still open
  when checked, waits for the DAP listener before reading its port and supplies
  the expected WebSocket Origin. It does not introduce a new inspector endpoint.
- [metro-mcp](https://github.com/steve228uk/metro-mcp), checked at v0.15.0, uses
  `metro-bridge`'s `CDPMultiplexer` to share a single upstream connection. It is
  a possible transport bridge, not evidence that js-debug handles Hermes.

## Reproduce the transport result

Install the fixture dependencies in a temporary directory, then run from there:

```sh
npm install ws @react-native/dev-middleware@0.87.1
node /path/to/nvim/spikes/react-native-dap/transport.mjs
```

The harness uses an ephemeral loopback port, closes sockets, and exits after
printing PASS. It does not start an emulator, Metro, or a real mobile app.

## Probe a real app

Run a development build and Metro, close any competing DevTools connection,
and run from the RN project (it must resolve the `ws` package):

```sh
node /path/to/nvim/spikes/react-native-dap/probe.mjs http://127.0.0.1:8081
```

With multiple targets, the probe prints their IDs and requires one as the next
argument. It supplies Origin, enables Runtime/Debugger, evaluates `1 + 41`, then
disables Debugger and disconnects. No target is selected implicitly when several
apps are connected. The same probe can target a metro-mcp CDP proxy URL.

Before promoting an RN configuration, use a real Hermes app to verify a TSX
source breakpoint, local-variable evaluation, step/continue, reload/reconnect,
and DevTools coexistence through the multiplexer. No running app/device was
available during this spike, so those results and any implementation estimate
remain open. React Native DevTools remains the documented working workflow.
