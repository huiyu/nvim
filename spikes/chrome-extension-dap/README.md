# Spike: debugging a Chrome extension from nvim-dap

> **Asked:** 2026-09-18 · **Stop condition:** a breakpoint that pauses in
> extension source, or a demonstrated blocker.
>
> **Scope:** the **adapter layer**, not any one project. Nothing here is specific
> to the extension that happened to be used as the subject; it applies to any
> Chrome/MV3 extension whatever framework builds it. Paths like
> `apps/extension/...` below are just that subject's.
>
> **Verdict (round 5, decisive): PR #2361 works — service worker breakpoints
> pause, with `extensionPath` as the only configuration.** Built the branch and
> attached: stopped in `parseSaveRequest`, frame resolved to the real
> `save-request.ts:11`, call stack through `background.ts:28`, and the extension
> page target owned too. No hand-tuned `webRoot`, no `sourceMapPathOverrides`.
> Everything below this line was measured against a *stock* js-debug and is
> history; the practical answer is "build that branch and point the adapter at it".
>
> **Superseded verdict: not with a stock js-debug — and upstream means it.**
> Chrome, CDP and the extension model block nothing: ~60 lines of raw CDP pause
> an MV3 service worker and read its stack and locals (round 3). Every wall is
> js-debug's own, and its maintainer closed browser-extension support as
> `*out-of-scope`, saying "I'm surprised it works at all". A community PR
> ([#2361](https://github.com/microsoft/vscode-js-debug/pull/2361), open,
> +708/-32) implements it properly.
>
> **Therefore: do not build a bridge.** Build that PR's branch and point the
> adapter at it, or wait on it. Writing one from scratch means redoing the parts
> js-debug already gets right in order to route around two gaps.
>
> **NOT answered:** why a *patched* js-debug verifies a worker breakpoint and
> then does not honour the pause (round 2) — most likely the `ServiceWorker`
> domain initialisation that PR #2361 handles by borrowing a page session;
> whether the extension *page* works once `webRoot` is corrected (round 1
> measured it with the wrong `webRoot`, so that result is suspect); whether
> headed Chrome differs — every run here was `--headless=new`.
>
> **Revision history:** r1 concluded "structurally unsupported" (**wrong**);
> r2 found the single filter line that causes it; r3 proved raw CDP works;
> r4 found the upstream history that explains all of it. The investigation log
> below is in that order — later rounds correct earlier ones.

## Upstream status — read this first (round 4)

The maintainer analysed this in 2023 (issue #945) and named **exactly the two
obstacles this spike rediscovered by reverse-engineering the minified bundle**:

> 1. We need to attach to browser-level frames and service workers, **currently
>    we filter and only attach to `page` types. This is easy to fix.**
> 2. Sources in extensions get some random URL prefix like
>    `chrome-extension://gmocg…/service-worker.js`. We don't have any way to map
>    this in the debugger, and having a definite ID is not trivial.
>
> I don't plan to support this in the foreseeable future, **though if anyone has
> better solutions to #2, I'm happy to reconsider.** — connor4312

And on #1794: *"We don't support debugging Chrome extensions with this debugger.
I'm surprised it works at all."*

So it is a deliberate scope decision, not an oversight — but not a rejection of
the idea either: obstacle 1 he calls easy, obstacle 2 he is open to.

### Why obstacle 2 is genuinely hard

Chrome derives an unpacked extension's ID by hashing the **absolute path of its
build directory**:

```
ID = sha256(absolute path) -> first 16 bytes -> each hex nibble mapped onto a-p
```

Verified against two IDs observed in this spike — both matched exactly. Move the
build directory and the ID changes; so does moving machines or re-cloning.

That is a chicken-and-egg problem: every file's URL is `chrome-extension://<id>/…`,
`sourceMapPathOverrides` is static configuration fixed before launch, and the id
is only known at runtime. Three ways out, none clean:

| Way | Cost |
|---|---|
| Declare `key` in the manifest → ID stable everywhere | Requires changing the manifest; most projects have no `key` |
| Hash the path | What PR #2361 falls back to, explicitly **best-effort**: Chrome hashes the path as it spells it internally (Windows: backslashes, upper-case drive) |
| Ask Chrome at runtime (`Extensions.loadUnpacked` returns the id) | What round 2 did — but it forces the debugger to *load* the extension rather than attach to a running one |

### The third obstacle, unstated but all over the PR

MV3 lifecycle. From PR #2361:

> MV3 extension service workers are torn down when idle, and a stopped worker has
> **no target at all** — so there is nothing to match until something causes it
> to start. `ServiceWorker.startWorker` starts it on demand. **The domain is not
> available on the browser session**, so this borrows a page target's session.

That one paragraph explains three separate mysteries: why #1794 reports "only the
first attach works"; why the community workaround in #1445 manually makes the
worker a *child of a popup*; and why round 2's patched adapter owned the worker
yet never paused — it made the worker a top-level target, bypassing the page
session the `ServiceWorker` domain needs.

### Community workaround (no patch required)

From #1445, reported working: open a second Chrome window → `chrome://extensions`
→ wait for the worker to go **inactive** (up to 30s) → open the extension's popup
→ DevTools opens → Application tab → click `start` on the worker → close DevTools
but keep the popup. The debugger then attaches to the worker **as a child of the
popup**, and breakpoints pause.

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

# 4. round 2 - service worker via a PATCHED adapter copy. Patch is one line:
#    wa=r=>e=>e.type==="page"&&…   ->   (e.type==="page"||e.type==="service_worker")&&…
#    Run the patched copy's dapDebugServer.js, then:
node sw-probe.mjs <dapPort> <cdpPort> <extOutDir> ~/Code/knotmark/tactify automatic
#    webRoot must be the BUILD OUTPUT dir, and build output must sit inside the
#    project (see the webRoot gotcha) or relative sources clamp and lose a segment.

# 5. round 3 - no js-debug at all; raw CDP pauses the worker
node cdp-direct-breakpoint.mjs <cdpPort> <extOutDir> <0-based line in background.js>
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


---

# Round 2: the service worker, re-examined

Round 1 said SW support was structurally absent. That was an inference from one
code fragment, and it was wrong.

## js-debug already has the machinery

```
serviceWorkerModel        attached / detached / dispose / onDidChange
CDP domain                ServiceWorker.enable / stopWorker / setForceUpdateOnPageLoad
event                     workerVersionUpdated
Du = new Set(["page","iframe","worker","service_worker"])   ← targetList() filter
```

The worker is kept out only by the attach-mode target filter:

```js
wa = r => e => e.type === "page" && !e.url.startsWith("edge://force-signin") && r(e)
if (t.targetSelection !== "pick") return i;
```

Likely a coverage gap rather than a decision: in VS Code's web-debugging world a
SW is typically a *child of a page* (PWA), and `Du` is used in `children()`. A
Chrome extension's worker is a browser-level target that hangs off no page, so
that path never reached it.

## What was tried

| Experiment | Result |
|---|---|
| `targetSelection: "pick"` | **No.** Candidates still come from the same page-only filter. |
| Patch `wa` to also admit `service_worker` | **Worker owned.** `js-debug owns: ["Service Worker chrome-extension://…/background.js", …]` |
| …then `loadedSources` on that session | **38 sources**, including `save-request.ts` |
| …then fix `webRoot` | **`BREAKPOINT VERIFIED`**, `exact match present: true` |
| …then run the code | **Still no pause.** |

The last row is the wall. The breakpoint binds to a real `.ts` line, the line
demonstrably executes — driving `retry_save` makes the worker answer
`{"ok":false}`, which is exactly what `background.ts` returns when
`parseSaveRequest` rejects the payload — and the debugger does not stop.

So the patch opens target ownership, sourcemap resolution and breakpoint
binding; something further down the worker path still does not honour the pause.
That last piece was not diagnosed.

## webRoot gotcha (independent of the patch)

js-debug maps `chrome-extension://<id>/background.js` onto `<webRoot>/background.js`
and resolves the map's relative sources (`../../src/x.ts`) from **there**. So
`webRoot` must be the **build output directory**, not the package root — with the
package root the `..`s walk two levels above it and every source lands outside
the workspace. Round 1's `loadedSources: 0` for the extension *page* may well be
the same mistake; that was never re-tested with a corrected webRoot.

Also: with output under `~/.config/nvim/spikes` and sources under `~/Code`, the
relative paths were six levels deep and clamped at the `chrome-extension://<id>/`
origin root, silently losing a path segment. Round 2 rebuilt under
`apps/extension/.output-spike` to match the real layout. Keep spike output in the
project's own tree.

## NOT answered in round 2

Why a verified breakpoint in the worker does not pause. Whether the extension
*page* works once `webRoot` points at the build output. Whether headed Chrome
differs — still every run was `--headless=new`.


---

# Round 3: raw CDP, no js-debug

Bypassing js-debug entirely and speaking CDP to the worker the way DevTools does:

```
Debugger.enable                                  → ok
Debugger.setBreakpointByUrl {lineNumber: 6883,   → {"breakpointId":"2:6883:0:background\\.js$",
                             urlRegex: "background\\.js$"}    "locations":[{"scriptId":"3","lineNumber":6883}]}
… send retry_save …
Debugger.paused                                  → parseSaveRequest @ 6884
Runtime.getProperties (local scope)              → value="Object", request=undefined, validId=undefined
Debugger.resume                                  → ok
```

**Chrome pauses an extension service worker for any CDP client.** The wall in
rounds 1-2 is js-debug's, not Chrome's, not CDP's, not the extension model's.

That also settles round 2's open question: js-debug verified a breakpoint on the
worker and then failed to pause on it. Since CDP honours the same pause from a
60-line client, that is an implementation gap in js-debug's worker path.

## What this does and does not buy

CDP hands over raw events and commands. What a debugger still needs on top:

- sourcemap translation both ways (`.ts` line ↔ generated line) — the generated
  position above is 6884, not `save-request.ts:11`
- breakpoint bookkeeping across worker restarts, which MV3 does constantly
- a UI for stack, scopes and stepping

That last one is exactly what nvim-dap already provides, which is why the sane
shape is still a DAP↔CDP bridge — either a fixed js-debug or a small purpose-built
one — rather than reimplementing DevTools in Lua.

**Feasibility is no longer the open question.** Cost and maintenance are.


---

# Round 5: PR #2361, built and measured — it works

Built the PR branch (`gulp dapDebugServer`, 911KB, carries `extensionPath` and
`wakeExtensionServiceWorker`) and attached with **only** `extensionPath` set:

```
[cdp] extension installed: foepkabbfgmfkepmdcblpenddoeehlbf
[dap] attach success: true
  [child1] owns: ["Service Worker chrome-extension://foepkabb…/background.js"]
  [child1] BREAKPOINT VERIFIED
  [child2] owns: ["chrome-extension://foepkabb…/tabs.html"]

*** STOPPED in child1 ***
   ServiceWorkerGlobalScope.parseSaveRequest @ …/src/features/save-all/save-request.ts:11
   <anonymous>                               @ …/entrypoints/background.ts:11

[result] worker owned: YES | STOPPED: YES
[result] config passed was ONLY: {"extensionPath": "…/.output-spike/chrome-mv3-dev"}
```

This closes every open question this spike carried:

| Was open | Now |
|---|---|
| Why does a patched js-debug verify a worker breakpoint and not pause? | PR handles it — `wakeExtensionServiceWorker` borrows a page session to init the `ServiceWorker` domain, which the round-2 patch bypassed |
| Does the extension *page* work once `webRoot` is right? | Its target is owned (child2). Pausing *in page code* was not separately asserted |
| Must `webRoot` be hand-set to the build output? | **No.** The PR resolves paths from `extensionPath` |

## What it takes to use it

1. Build the branch: `git fetch origin refs/pull/2361/head && gulp dapDebugServer`
   → `dist/src/dapDebugServer.js`
2. Point the nvim-dap adapter's `command` at that file instead of mason's
3. One configuration carrying `extensionPath` = the **build output** directory

**Launch mode is the part that does not work on current Chrome**: the PR passes
`--load-extension`, removed in Chrome 137+ (retested here with
`--enable-unsafe-extension-debugging` — still zero targets). Attach mode is
unaffected, and the extension can be installed over CDP with
`Extensions.loadUnpacked`, which this spike used throughout and which the PR
already uses for hot reload. Routing initial load through it would revive launch
mode — worth reporting upstream.

## Still not answered

Pausing inside extension *page* code (only the worker was asserted). Headed
Chrome — every run here was `--headless=new`. Whether the PR's auto-reload
(`fs.watch` on the extension dir + `Extensions.loadUnpacked`, 400ms debounce)
works in attach mode; its own comment says it is for launched browsers.
