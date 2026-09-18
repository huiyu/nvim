# Spike: Can nvim-dap (pwa-chrome) hit a breakpoint in WXT extension source?

> **Asked:** 2026-09-18 · **Stop condition:** a DAP `stopped` event whose frame resolves to a real `.ts` path, or a demonstrated blocker
> **Verdict:** **answered — do not build it.** js-debug attaches to a `chrome-extension://` page target and then parses **zero scripts** in that session, so no breakpoint can ever bind. The same js-debug, same harness, same machine hits breakpoints on an `http://` page every time. For the service worker js-debug does not even spawn a session.
> **NOT answered:** whether headed (non-headless) Chrome behaves differently — every run here was `--headless=new`; whether nvim-dap's own multi-session implementation passes some option this hand-written client did not (the harness was proven equivalent on the control, but not identical); what `wxt dev`'s extension reload does to a live DAP session, which was never reached.
> **Unblocks:** scope for `~/.config/nvim` — specifically, it rules the Chrome-extension half OUT and promotes the adapter-registration bug below to the real work.

## Answers

| # | Question | Answer |
|---|---|---|
| Q1 | Does Chrome 153 still honor `--load-extension`? | **NO.** Two runs, including `--disable-features=DisableLoadExtensionCommandLineSwitch`, left the extension uninstalled. WXT 0.21.4 agrees — it prints *"Load … as an unpacked extension manually"*. |
| Q1b | Is there a replacement? | **YES — `Extensions.loadUnpacked` over CDP.** Returns an extension id and genuinely installs it. An automation path exists. |
| Q2 | Are the extension's targets exposed over CDP? | **YES.** `service_worker /background.js` appears immediately on install; `page /tabs.html` once opened. |
| Q3 | Does WXT's sourcemap resolve to real `.ts` files? | **YES, for `wxt dev` only.** 31/31 sources resolved, `sourcesContent` complete. **`wxt build -m development` emits no sourcemap at all** — a build-mode trap. |
| Q4 | Does a breakpoint bind and hit? | **Plain page: YES** — stopped at `app.js:2`, `loadedSources: 1` with the real on-disk path. **Extension page: NO** — target owned (thread `Tactify — Saved Tabs`, React confirmed mounted) but `loadedSources: 0`. **Service worker: NO** — no session spawned. |

Configurations tried against the extension page, none of which changed
`loadedSources: 0`: `sourceMapPathOverrides`, `pathMapping`, `outFiles`,
`resolveSourceMapLocations: null`, `urlFilter`, `__workspaceFolder`, and forcing
all of them into the child session rather than only the root.

## The finding that outranks all of the above

**JS/TS debugging is not wired up in this config at all.** In a real `nvim -u init.lua`:

```
adapters: codelldb, delve, python
pwa-chrome adapter: nil
configurations: zig, cpp, c, python, rust, go, swift   (no javascript/typescript)
```

Root cause: `mason-nvim-dap`'s `mappings/adapters/` ships `chrome.lua`, `node2.lua`
and `firefox.lua` — but **no `js.lua`**. The `['js'] = 'js-debug-adapter'` entry in
`mappings/source.lua` only decides *which package mason installs*; it registers no
adapter. So `lang/typescript.lua`'s `handlers = { ["js"] = {} }` installs the
binary and stops there.

That file's comment ("A single adapter covers BOTH runtimes: `pwa-node` … and
`pwa-chrome` …") describes an intent that never took effect. Today `<leader>dc`
cannot debug a Node process, a vitest run, or a browser tab.

## Architecture note worth keeping

`wxt dev` splits the extension across two loading mechanisms, and they need
opposite debug config:

- **Page** (`tabs.html`) — the HTML is a shell; the real code is fetched from the
  vite dev server: `<script type="module" src="http://localhost:3000/entrypoints/tabs/main.tsx">`.
  Kill the dev server and the page still opens with a correct `<title>` while no
  application code ever runs.
- **Service worker** (`background.js`) — genuinely bundled into the extension,
  991KB with an inline sourcemap, because a worker cannot import over http.

Three experiment runs were invalidated by not knowing this: the dev server had
been stopped, so "the breakpoint does not bind" was measuring an empty page.

## Method notes (which earlier results are void)

1. js-debug is a **multi-session** adapter. The root session owns no targets; it
   asks the client to spawn a child per target via the `startDebugging` reverse
   request, and answers `attach` only after `configurationDone`. Harness v1–v2 did
   neither, so `threads` was always `[]` — a harness flaw, not evidence.
2. `loadedSources` was validated as a judgment criterion on the known-good control
   (returns 1 real path there), so the extension's `0` is a real measurement.
3. Everything before `dap-v3.mjs`, and every extension run before the dev server
   was restarted, is void.

## Reproduce

```sh
# 1. dev build WITH sourcemaps, dev server left RUNNING (both matter)
cd ~/Code/knotmark/tactify/apps/extension && npx wxt   # `wxt dev` parses "dev" as the root arg

# 2. positive control - proves the harness can hit a breakpoint
node dap-v3.mjs <dapPort> <cdpPort> ./web/app.js 2 web ./web http://127.0.0.1:8790/index.html

# 3. the subject
node dap-v6.mjs <dapPort> <cdpPort> <extOutDir> ~/Code/knotmark/tactify page
node dap-v6.mjs <dapPort> <cdpPort> <extOutDir> ~/Code/knotmark/tactify worker
```

Chrome needs `--remote-debugging-port` and a **separate `--user-data-dir`**; without
the latter a second Chrome hands the URL to the running instance and never opens the
port. js-debug server:
`node ~/.local/share/nvim/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js <port>`

## Not product code

Throwaway. No tests, no error handling, happy path only. The verdict says do not
build the extension entry point, so nothing here graduates.

## Leftovers to delete

`output/` is a rebuilt extension and `web/` is the control fixture. The Chrome
profile directories are pure browser cache — roughly 900MB — and carry no knowledge:

```sh
rm -rf ~/.config/nvim/spikes/chrome-extension-dap/{chrome-profile*,prof*,p_*,output,*.log}
```

Add `spikes/` to `.gitignore` if this directory is kept at all.
