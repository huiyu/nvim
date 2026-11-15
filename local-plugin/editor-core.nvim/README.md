# editor-core.nvim

Editor preferences, foundational mappings/autocommands, window/buffer operations
and the keybinding guide. Requiring the module is inert. A high-priority
`lazy = false` local spec calls `require("editor_core").setup(opts)` once.

Options: `options` (public Vim option overrides), `theme` (UI options/glyphs),
`formatting` (autoformat), `behaviors` (optional input-method/cursor/yank/autoread
behavior), `keymaps` (leader/localleader, core/actions/open declarations), and
`url.buffer_dir` (optional host directory callback). `keymaps = false` installs
no mappings; `keymaps.core = false` / `actions = false` disable each group.

Host values live under `lua/config/`; the runtime owns private compatibility
settings and behavior. `editor_core.options`, `keymaps`, `autocmds` apply them;
which-key renders metadata and is not required for actions or the generated
`editor_core.keyguide.show()` guide. Oil, Snacks and Aerial specs translate the
shared open declarations explicitly into their supported upstream actions.

The host passes dashboard data to `editor_core.dashboard.build(data)` from the
Snacks spec. Window viewport behavior belongs here; quotes/keys belong in config.
Reusable window, buffer, terminal-text, URL, DAP and LSP operations are documented
in the host's `docs/UTILITIES.md`. They import no private host config/util modules.
