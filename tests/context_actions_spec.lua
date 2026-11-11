local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return require("which-key.config").loaded end), "which-key setup finishes")
local View = require("which-key.view")
local State = require("which-key.state")

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true)
end
local general = {}
for _, lhs in ipairs({ ",h", ",j", ",k", ",l" }) do general[lhs] = mapping(lhs).callback end

local function buffer(ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "." .. ft)
  vim.bo.filetype = ft
  return buf
end

-- Read and render the real trie, including implicit ,d / ,L groups. The
-- source buffer must remain current while the floating menu is visible.
local function popup(prefix)
  local mode = require("which-key.buf").get({ mode = "n", update = true })
  local node = mode.tree:find(prefix or ",")
  local rows, owners, title = {}, {}, nil
  for _, child in ipairs(node:children()) do rows[#rows + 1] = View.item(child, { parent = node }) end
  View.sort(rows)
  for _, row in ipairs(rows) do
    if row.key == "" then title = row.desc:sub(#"── " + 1)
    else owners[row.keys] = title end
  end
  vim.o.lines, vim.o.columns = 100, 140
  State.state = { mode = mode, node = node, filter = {}, show = true, started = vim.uv.hrtime() }
  View.show()
  local rendered = table.concat(vim.api.nvim_buf_get_lines(View.view.buf, 0, -1, false), "\n")
  State.stop()
  return owners, rendered
end

t.eq(vim.g.maplocalleader, ",", "filetype actions use comma")
for _, case in ipairs({
  { "python", { ",o", ",v" }, "Python · imports/environment" },
  { "go", { ",o", ",G" }, "Go · imports/server" },
  { "c", { ",H" }, "C/C++ · files" },
  { "cpp", { ",H" }, "C/C++ · files" },
  { "markdown", { ",p", ",m" }, "Markdown · preview" },
  { "dart", { ",d" }, "Dart/Flutter · runtime" },
  { "tex", { ",b", ",s", ",K", ",E" }, "LaTeX · build" },
  { "plaintex", { ",v", ",t" }, "LaTeX · preview/tools" },
}) do
  local ft, keys, heading = unpack(case)
  local buf = buffer(ft)
  local owners, rendered = popup()
  for _, key in ipairs(keys) do
    t.eq(owners[key], heading, ft .. ": " .. key .. " is in the right operation section")
  end
  t.ok(rendered:find("── " .. heading, 1, true), ft .. ": heading is rendered in the real popup")
  t.eq(vim.api.nvim_get_current_buf(), buf, "popup keeps its source buffer current")
  for lhs, callback in pairs(general) do
    t.eq(mapping(lhs).callback, callback, ft .. ": " .. lhs .. " retains general editing behavior")
  end
  t.eq(mapping(",e"), {}, ft .. ": extract prefix is not replaced by an action")
  local obsolete, ambiguous = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if m.lhs:sub(1, 1) == "\\" then obsolete[#obsolete + 1] = m.lhs end
    if m.lhs:match("^,[hlkc].+") then ambiguous[#ambiguous + 1] = m.lhs end
  end
  t.eq(obsolete, {}, ft .. ": no old backslash mappings")
  t.eq(ambiguous, {}, ft .. ": no longer candidates delay general editing keys")
  t.eq(mapping(",1"), {}, ft .. ": terminal digits do not leak into files")
end

-- Selected-region compilation retains its Visual binding and full VimTeX
-- commands do not make ,l wait. Test the actual plugin-created mappings.
buffer("tex")
t.eq(mapping(",Ll").rhs:lower(), "<plug>(vimtex-compile)", "VimTeX continuous compiler lives under ,L")
t.eq(mapping(",LL", "x").rhs:lower(), "<plug>(vimtex-compile-selected)", "VimTeX selected compilation keeps Visual mode")
t.eq(mapping(",E").rhs:lower(), "<cmd>vimtexerrors<cr>", "errors has a direct shortcut without shadowing extraction")
local owners = popup()
t.eq(owners[",L"], "LaTeX · preview/tools", "VimTeX group has a context section")
t.eq(owners[",v"], "LaTeX · preview/tools", "shared ,v uses the current language heading")
buffer("python")
owners = popup()
t.eq(owners[",v"], "Python · imports/environment", "switching back restores the Python heading")
t.eq(mapping(",Ll"), {}, "VimTeX mappings stay in TeX buffers")

-- Language actions are worded like the rest of the menu: sentence case, no
-- qualifier repeating the heading above them, and "…" where the key asks first.
for _, case in ipairs({
  { "python", ",o", "[LSP] Organize imports" },
  { "python", ",v", "Select virtualenv…" },
  { "go", ",o", "[LSP] Organize imports" },
  { "go", ",G", "[LSP] Rebuild gopls index" },
  { "c", ",H", "[LSP] Switch source/header" },
  { "dart", ",dr", "Hot reload" },
  { "dart", ",dR", "Hot restart (Flutter only)" },
}) do
  local ft, lhs, want = unpack(case)
  buffer(ft)
  t.eq(mapping(lhs).desc, want, ft .. ": " .. lhs .. " is " .. want)
end
buffer("dart")
local _, dart_menu = popup()
t.ok(dart_menu:find("Hot reload/restart", 1, true), "dart: the ,d group row names both actions")

buffer("text")
local _, rendered = popup()
t.ok(not rendered:find("Python ·", 1, true) and not rendered:find("LaTeX ·", 1, true),
  "plain text does not advertise other filetypes' operations")

-- A chat buffer. CodeCompanion maps ,s ,X ,q ,z on each chat it creates, so
-- stand-ins take their place here (tests/companion_spec.lua pins the real
-- ones). The Chat heading must come before the unfiltered CodeDiff and Review
-- sections, which declare z and X too.
local chat = buffer("codecompanion")
for _, lhs in ipairs({ ",s", ",X", ",q", ",z" }) do
  vim.keymap.set("n", lhs, "<Nop>", { buffer = chat, desc = "stand-in" })
end
owners = popup()
for _, lhs in ipairs({ ",s", ",X", ",q", ",z", ",m" }) do
  t.eq(owners[lhs], "Chat · conversation/rendering", "codecompanion: " .. lhs .. " is under the Chat heading")
end
for lhs, callback in pairs(general) do
  t.eq(mapping(lhs).callback, callback, "codecompanion: " .. lhs .. " retains general editing behavior")
end

-- Plugin-provided localleader defaults must not shadow general comma actions.
-- Open the actual editable search panel, inspect its mappings and close it
-- through the new key rather than just checking the lazy options table.
vim.cmd.GrugFar()
local search, search_name = require("grug-far").get_instance(vim.api.nvim_get_current_buf())
local ready = false
search:when_ready(function() ready = true end)
t.ok(vim.wait(1000, function() return ready end), "search panel finishes rendering")
vim.cmd.stopinsert()
t.eq(vim.bo.filetype, "grug-far", "real search panel opens")
for lhs, callback in pairs(general) do
  t.eq(mapping(lhs).callback, callback, "search panel preserves " .. lhs)
end
local unexpected = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if m.lhs:sub(1, 1) == "\\" or (m.lhs:sub(1, 1) == "," and #m.lhs > 1 and m.lhs:sub(1, 2) ~= ",S") then
    unexpected[#unexpected + 1] = m.lhs
  end
end
t.eq(unexpected, {}, "all search-local prefixed actions use ,S without shadowing editing")
owners, rendered = popup()
t.eq(owners[",S"], "format/replace", "search subgroup is beside its search entry points")
t.ok(rendered:find("Search panel", 1, true), "search subgroup has a readable label")
owners = popup(",S")
for _, case in ipairs({
  { ",Sr", "replace/sync", "Replace" },
  { ",Sl", "replace/sync", "Sync Line" },
  { ",Sq", "results", "Quickfix" },
  { ",St", "history", "History Open" },
  { ",Sf", "search/panel", "Refresh" },
}) do
  t.eq(owners[case[1]], case[2], case[1] .. " has the right operation section")
  t.eq(mapping(case[1]).desc, case[3], case[1] .. " invokes the plugin action")
end
local panel = vim.api.nvim_get_current_buf()
vim.api.nvim_feedkeys(",Sc", "xt", false)
t.ok(not vim.api.nvim_buf_is_valid(panel), ",Sc closes the real search buffer")
t.ok(not require("grug-far").has_instance(search_name), "closing cleans up the search instance")
buffer("text")
local mode = require("which-key.buf").get({ mode = "n", update = true })
t.eq(mode.tree:find(",S"), nil, "search subgroup does not leak into ordinary files")

-- A real terminal uses the same menu, without changing terminal input.
local job = vim.fn.jobstart({ "sh", "-c", "cat" }, { term = true })
owners, rendered = popup()
t.eq(owners[",1"], "Terminal · sessions", "terminal sessions have their own section")
t.eq(mapping(",1", "t"), {}, "comma digits leave terminal input untouched")
vim.fn.jobstop(job)

-- Bare comma still performs native reverse f/t after timeout; use a remapped
-- normal-mode keystroke following the built-in forward motion.
buffer("text")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a-b-c" })
vim.cmd("normal! 02f-")
vim.api.nvim_feedkeys(",", "xt", false)
t.eq(vim.api.nvim_win_get_cursor(0)[2], 1, "bare comma retains native reverse f/t")

-- Filetype plugins' own motions read as words, not code: Python's ]] showed
-- ":<C-U>call <SNR>27_Python_jump(...)" and VimTeX's "vimtex-][)". The desc is
-- written onto the buffer's own mapping (whichkey_spec's filetype_descs), mode
-- by mode, and the mapping is otherwise untouched.
for _, case in ipairs({
  { "python", "]]", "n", "Next top-level class/def start", "Python_jump" },
  { "python", "[]", "o", "Prev top-level class/def end", "Python_jump" },
  { "python", "]m", "x", "Next class/def start", "Python_jump" },
  { "go", "]]", "n", "Next type/func start", "GoFindSection" },
  { "go", "[]", "o", "Prev type/func end", "GoFindSection" },
  { "rust", "]]", "x", "Next top-level block", "rust#Jump" },
  { "vim", "][", "n", "Next function end", "search(" },
  { "vim", '["', "x", "Prev comment", "search(" },
  { "tex", "]n", "o", "Next math zone start", "vimtex-]n" },
  { "tex", "[R", "x", "Prev frame end", "vimtex-[R" },
  { "tex", "]m", "n", "Next environment start", "vimtex-]m" },
  { "tex", "]*", "o", "Next comment end", "vimtex-]*" },
  { "tex", "ac", "x", "command", "vimtex-ac" },
  { "tex", "im", "o", "inner item", "vimtex-im" },
  { "markdown", "[[", "x", "Prev section", "search(" },
}) do
  local ft, lhs, mode, want, rhs = unpack(case)
  buffer(ft)
  local m = mapping(lhs, mode)
  t.eq({ m.desc, m.buffer }, { want, 1 }, ("%s: %s %s is %q"):format(ft, mode, lhs, want))
  t.ok((m.rhs or ""):find(rhs, 1, true), ("%s: %s %s still runs %s"):format(ft, mode, lhs, rhs))
end
buffer("python")
local _, brackets = popup("]")
t.ok(brackets:find("Next top-level class/def start", 1, true) and not brackets:find("Python_jump", 1, true),
  "python: the ] popup shows the motion's words, not its code")
-- A key VimTeX leaves to a global map keeps the global map's own desc.
buffer("tex")
t.eq(mapping("]n", "x").buffer, 0, "tex: Visual ]n stays Nvim's node selection")
local section = mapping("]]")
t.ok(section.buffer == 1 or section.desc ~= "Next section start",
  "tex: a global ]] is never relabelled as VimTeX's section motion")
-- The desc belongs to the mapping, so it goes with the filetype.
local py = buffer("python")
vim.bo[py].filetype = "text"
t.ok(mapping("]]").desc ~= "Next top-level class/def start", "leaving python drops its ]] desc")

-- gO is the heading outline in markdown, help, checkhealth and man: their own
-- mapping shows, under its own heading, not Nvim's [LSP] default.
for _, ft in ipairs({ "markdown", "help", "checkhealth", "man" }) do
  buffer(ft)
  t.eq({ mapping("gO").desc, mapping("gO").buffer }, { "Show outline", 1 }, ft .. ": gO is the outline")
  owners = popup("g")
  t.eq(owners["gO"], "outline", ft .. ": gO is not under the LSP heading")
end
buffer("lua")
t.eq({ mapping("gO").desc, mapping("gO").buffer }, { "[LSP] Document symbols (Nvim default)", 0 },
  "elsewhere gO is Nvim's own, with a readable desc")
owners = popup("g")
t.eq(owners["gO"], "LSP", "and sits under LSP")

-- Views that put their own actions on g and , get a heading of their own,
-- ahead of the LSP, lines and refactor sections that declare the same keys.
-- Stand-ins take the place of the plugins' buffer-local maps.
for _, case in ipairs({
  { "oil", { "gs", "g." }, "oil · listing" },
  { "codediff-explorer", { "gs", "gu" }, "CodeDiff · panel" },
  { "codecompanion", { "gd", "gr", "gy", "gh" }, "Chat · conversation/context" },
  { "lazy", { "gb", "gl", ",l", ",i" }, "Lazy · plugin" },
}) do
  local ft, keys, heading = unpack(case)
  local buf = buffer(ft)
  for _, lhs in ipairs(keys) do
    vim.keymap.set("n", lhs, "<Nop>", { buffer = buf, desc = "stand-in" })
  end
  local g_owners, comma_owners = popup("g"), popup(",")
  for _, lhs in ipairs(keys) do
    local got = lhs:sub(1, 1) == "g" and g_owners[lhs] or comma_owners[lhs]
    t.eq(got, heading, ("%s: %s is under %s"):format(ft, lhs, heading))
  end
  -- The chat leaves gS (splitjoin) and gx (open URL) global: they keep
  -- their own place rather than the chat's heading.
  if ft == "codecompanion" then
    t.eq({ g_owners["gS"], g_owners["gx"] }, { "edit", "others" },
      "codecompanion: the global gS and gx are not filed under Chat")
  end
end

for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
t.done()
