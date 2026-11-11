-- The descriptions of the keys under a which-key popup are their interface
-- (#30, part 2), so they are worded one way everywhere: one verb per act
-- (Close a window or view, Delete a buffer, Discard a change), one word per
-- scope ("file" the current file, "cwd" Nvim's working directory, "repo" the
-- Git repository, "here" the file's directory), no articles, and "…" only on a
-- key that asks something before it acts. This pins the editor, Git, GitHub
-- and window keys; tests/ai_keymap_spec.lua holds <leader>a to the same rules,
-- and the CodeDiff, chat and LSP specs pin their own views.
local t = dofile("tests/helper.lua")

-- Entries with an RHS in lua/whichkey_spec.lua become keymaps once which-key's
-- scheduled loader has run (as in tests/escape_mapping_spec.lua).
vim.cmd("Lazy! load which-key.nvim")
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
vim.wait(100, function() return vim.fn.maparg("sd", "n") ~= "" end)

local function desc(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true).desc
end
local function expect(want, mode)
  for lhs, d in pairs(want) do
    t.eq(desc(lhs, mode), d, ("%s%s is %q"):format(mode and mode ~= "n" and (mode .. " ") or "", lhs, d))
  end
end

-- Windows close, buffers are deleted; twins read alike.
expect({
  sd = "Close window",
  so = "Close other windows",
  sw = "Previous window",
  se = "Editor window (toggle back)",
  ["<C-,>"] = "Editor window (toggle back)",
  ["<leader><tab>d"] = "Close tab",
  ["<leader><tab>f"] = "First tab",
  ["<leader><tab>l"] = "Last tab",
  ["<leader><tab>a"] = "Last used tab (alternate)",
  [";a"] = "Last used buffer (alternate)",
  ["<leader>bp"] = "Toggle pin",
  ["<leader>bP"] = "Delete unpinned buffers",
  ["<leader>bl"] = "Delete buffers to left",
  ["<leader>br"] = "Delete buffers to right",
})
t.eq(desc("<C-,>", "t"), "Editor window (toggle back)", "terminal <C-,> is worded as se")
-- Read through :command, which prints the desc as given (see dap_actions_spec).
local function command_desc(name)
  return vim.api.nvim_exec2("command " .. name, { output = true }).output
end
t.ok(command_desc("WindowFocusEditor"):find("Editor window (toggle back)", 1, true) ~= nil,
  ":WindowFocusEditor is worded as se and <C-,>")
t.ok(command_desc("WindowCloseCurrent"):find("Close window", 1, true) ~= nil,
  ":WindowCloseCurrent is worded as sd")

-- Harpoon: the add key says it adds, and "pinned" stays bufferline's word.
expect({
  [";H"] = "Add file to Harpoon",
  [";h"] = "Harpoon menu",
  [";1"] = "Harpoon file 1",
  [";9"] = "Harpoon file 9",
})

-- Scope words on `;` and <leader>y.
expect({
  [";f"] = "Find file in cwd",
  [";i"] = "Find file in cwd (respect gitignore)",
  [";F"] = "Find file from here (file's dir)",
  [";r"] = "Recent files in cwd",
  [";/"] = "Search in cwd",
  [";?"] = "Search in cwd (respect gitignore)",
  [";D"] = "Search from here (file's dir)",
  [";l"] = "Lines in file",
  [";o"] = "File manager (oil, float)",
  ["-"] = "Parent directory (oil)",
  [";P"] = "Find Markdown file in cwd → preview",
  ["<leader>yr"] = "Yank file path (repo-relative)",
})

-- Git: one scope word per history key, one verb (Discard) for throwing a
-- change away.
expect({
  ["<leader>gc"] = "File commits",
  ["<leader>gC"] = "Repo commits",
  ["<leader>gf"] = "File history (Lazygit)",
  ["<leader>gL"] = "Blame file",
  ["<leader>gr"] = "Discard hunk",
  ["<leader>gR"] = "Discard file changes",
  ["<leader>gB"] = "Open in browser (file or commit)",
})
t.eq(desc("<leader>gr", "x"), "Discard selected lines", "x <leader>gr discards the selected lines")

-- <leader>G: the heading already says GitHub, so no row repeats it; the keys
-- that leave Nvim say "(browser)", and "open" is only an issue or PR state.
expect({
  ["<leader>Gr"] = "Repo (browser)",
  ["<leader>Gf"] = "File (browser)",
  ["<leader>GF"] = "File permalink (browser)",
  ["<leader>Ga"] = "Workflow runs (browser)",
  ["<leader>Gn"] = "Notifications (browser)",
  ["<leader>Gi"] = "Issues (open)",
  ["<leader>GI"] = "Issues (all)",
  ["<leader>Gp"] = "PRs (open)",
  ["<leader>GP"] = "PRs (all)",
  ["<leader>Gc"] = "Current PR actions…",
  ["<leader>Gs"] = "Status (gh status)",
})
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  local lhs = vim.fn.keytrans(vim.keycode(m.lhs))
  if lhs:find("^<Space>G") then
    t.ok(not (m.desc or ""):find("GitHub", 1, true), lhs .. " does not repeat the GitHub heading")
  end
end

-- Toggle only where the key toggles; the quickfix and location lists are
-- named one way, window or picker.
expect({
  [",O"] = "Toggle code outline",
  ["<leader>xq"] = "Toggle quickfix window",
  ["<leader>xl"] = "Toggle location list window",
  ["<leader>xQ"] = "Quickfix list (picker)",
  ["<leader>xL"] = "Location list (picker)",
})

-- Sessions, put/increment variants, and the keys that ask first.
expect({
  ["<leader>sl"] = "Load last session",
  ["<leader>s."] = "Load cwd session",
  ["<leader>ss"] = "Save session",
  gp = "Put after (cursor after text)",
  gP = "Put before (cursor after text)",
  [">p"] = "Put below and indent right",
  ["g<C-A>"] = "Increment (progressive)",
  ["g<C-X>"] = "Decrement (progressive)",
  ["<leader>mM"] = "Man page…",
  [",R"] = "Select refactor…",
  [",ef"] = "Extract function…",
  [",eF"] = "Extract function to file…",
  [",ex"] = "Extract variable…",
  [",i"] = "Inline variable",
})

-- Proper nouns keep their capital; a buffer-local toggle names its scope "file".
expect({
  ["<leader>uT"] = "Toggle Treesitter highlight",
  ["<leader>uF"] = "Toggle autoformat (file)",
  F = "Flash Treesitter",
})

-- Maps that had no desc at all, so <leader>mk showed a blank row.
t.eq(desc("<S-CR>", "t"), "Send Shift+Enter (newline) to terminal", "terminal <S-CR> has a desc")
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(scratch)
vim.bo[scratch].filetype = "startuptime"
local q = vim.fn.maparg("q", "n", false, true)
t.ok(q.buffer == 1 and q.desc == "Close window", "close_with_q's q has a desc")
local guide = vim.fn.maparg("<leader>?", "n", false, true)
guide.callback()
local float = vim.api.nvim_get_current_win()
t.ok(vim.api.nvim_win_get_config(float).relative ~= "", "<leader>? opens the guide float")
for _, lhs in ipairs({ "q", "<Esc>" }) do
  local map = vim.fn.maparg(lhs, "n", false, true)
  t.ok(map.buffer == 1 and map.desc == "Close keybinding guide", "the guide's " .. lhs .. " has a desc")
end
vim.api.nvim_win_close(float, true)

-- The dashboard is a view with its own Title Case, but its two browser keys
-- no longer share the "Open …" label with the picker sections beside them.
local plugin = require("lazy.core.config").plugins["snacks.nvim"]
local opts = require("lazy.core.plugin").values(plugin, "opts", false)
local dash = {}
for _, k in ipairs(opts.dashboard.preset.keys) do dash[k.key] = k.desc end
t.eq({ dash.i, dash.o }, { "Issues (browser)", "PRs (browser)" }, "dashboard i/o say they open the browser")

t.done()
