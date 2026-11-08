-- Guards the global options whose effect reaches past a single buffer.
--
-- Each of these was wrong in a way no startup check could see: `ss`/`sv`
-- split above/left while their descs said below/right, a line with an ERROR
-- and a HINT could show the HINT in its one diagnostic cell, the Lua ftplugin
-- leaked `iskeyword`/`whichwrap` into every buffer opened after it, and JSON
-- lost its quotes to the global conceallevel.
local t = dofile("tests/helper.lua")
require("lazy").load({ plugins = { "which-key.nvim" } })
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
t.ok(vim.wait(1000, function() return require("which-key.config").loaded end), "which-key setup finishes")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function file(name, lines)
  local path = root .. "/" .. name
  vim.fn.writefile(lines, path)
  return path
end

local function top(win) return vim.fn.win_screenpos(win)[1] end
local function left(win) return vim.fn.win_screenpos(win)[2] end

-- Splits: ss and sv are the plain commands, and the options place them.
t.eq(vim.fn.maparg("ss", "n"), "<Cmd>split<CR>", "ss is a plain :split")
t.eq(vim.fn.maparg("sv", "n"), "<Cmd>vsplit<CR>", "sv is a plain :vsplit")
vim.cmd("tabnew")
local origin = vim.api.nvim_get_current_win()
vim.cmd("split")
local below = vim.api.nvim_get_current_win()
t.ok(top(below) > top(origin) and left(below) == left(origin), ":split opens below the current window")
vim.cmd("close")
vim.cmd("vsplit")
local right = vim.api.nvim_get_current_win()
t.ok(left(right) > left(origin) and top(right) == top(origin), ":vsplit opens to the right")
vim.cmd("close")

-- ,x shares the plain split: its terminal lands below the file it runs.
local run = require("util.run")
run.register("options_probe", function() return "true" end)
vim.cmd.edit(vim.fn.fnameescape(file("run.probe", { "x" })))
vim.bo.filetype = "options_probe"
local source = vim.api.nvim_get_current_win()
run.run_current()
local term = vim.api.nvim_get_current_win()
t.eq(vim.bo[vim.api.nvim_win_get_buf(term)].buftype, "terminal", ",x opens a terminal")
t.ok(term ~= source and top(term) > top(source), "and puts it below the file it runs")
local term_buf = vim.api.nvim_win_get_buf(term)
vim.cmd("tabclose")
vim.api.nvim_buf_delete(term_buf, { force = true })

-- Diagnostics: one config for every source, with the statusline's glyphs.
local config = vim.diagnostic.config()
local S = vim.diagnostic.severity
t.eq(config.severity_sort, true, "diagnostics sort by severity")
t.eq({ config.virtual_text, config.virtual_lines }, { false, false },
  "virtual text and virtual lines stay off")
local symbols
for _, component in ipairs(require("lualine").get_config().sections.lualine_x) do
  if type(component) == "table" and component[1] == "diagnostics" then symbols = component.symbols end
end
t.eq(symbols and {
  config.signs.text[S.ERROR] .. " ", config.signs.text[S.WARN] .. " ",
  config.signs.text[S.INFO] .. " ", config.signs.text[S.HINT] .. " ",
}, symbols and { symbols.error, symbols.warn, symbols.info, symbols.hint },
  "gutter signs use the glyphs lualine counts diagnostics with")

-- statuscol keeps one diagnostic sign per line, the highest-priority one; it
-- computes its signs once per window per redraw, and a headless run never
-- redraws, so each look goes through a fresh window. No filetype on purpose:
-- statuscol skips nofile buffers, and no server or linter takes this one.
vim.cmd.edit(vim.fn.fnameescape(file("signs", { "one", "two" })))
local ns = vim.api.nvim_create_namespace("options_spec")
local function diagnostic_cell(list)
  vim.diagnostic.reset(ns, 0)
  vim.diagnostic.set(ns, 0, list)
  vim.cmd("split")
  local column = vim.api.nvim_eval_statusline(vim.wo.statuscolumn, { winid = 0, use_statuscol_lnum = 1 }).str
  vim.cmd("close")
  return vim.fn.strcharpart(column, 0, 1)
end
local error_sign = config.signs.text[S.ERROR]
t.ok(vim.wo.statuscolumn ~= "", "statuscol draws this window's gutter")
t.eq(diagnostic_cell({
  { lnum = 0, col = 0, severity = S.ERROR, message = "error" },
  { lnum = 0, col = 2, severity = S.HINT, message = "hint" },
}), error_sign, "an ERROR wins the cell over a later HINT")
t.eq(diagnostic_cell({
  { lnum = 0, col = 0, severity = S.HINT, message = "hint" },
  { lnum = 0, col = 2, severity = S.ERROR, message = "error" },
}), error_sign, "and over an earlier HINT")
vim.diagnostic.reset(ns, 0)

-- The Lua ftplugin keeps its settings to the Lua buffer.
local default_iskeyword = vim.go.iskeyword
local default_whichwrap = vim.go.whichwrap
vim.cmd.edit(vim.fn.fnameescape(file("probe.lua", { "local n = 1", "return n-1" })))
t.eq(vim.bo.filetype, "lua", "a Lua file runs the Lua ftplugin")
t.eq(vim.bo.formatoptions:find("[cro]"), nil, "which still drops c/r/o from formatoptions")
t.ok(not vim.list_contains(vim.split(vim.bo.iskeyword, ","), "-"), "Lua's iskeyword has no '-': n-1 is three words")
vim.cmd.edit(vim.fn.fnameescape(file("after.txt", { "a-b" })))
t.eq(vim.bo.iskeyword, default_iskeyword, "a buffer opened after it keeps the default iskeyword")
vim.cmd("enew")
t.eq(vim.bo.iskeyword, default_iskeyword, "and so does a new empty one")
t.eq(vim.go.whichwrap, default_whichwrap, "whichwrap keeps Nvim's default after a Lua file")
t.eq(vim.go.whichwrap, "b,s", "which is h/l stopping at the line edge")

-- Conceal: JSON shows its quotes; LaTeX keeps the global level for VimTeX.
t.eq(vim.go.conceallevel, 2, "the global conceallevel stays 2")
for _, name in ipairs({ "probe.json", "probe.jsonc", "probe.json5" }) do
  vim.cmd.edit(vim.fn.fnameescape(file(name, { "{", '  "name": "x"', "}" })))
  t.eq(vim.wo.conceallevel, 0, vim.bo.filetype .. " shows its quotes")
end
vim.cmd.edit(vim.fn.fnameescape(file("probe.tex", { "\\documentclass{article}", "\\begin{document}", "$\\alpha$", "\\end{document}" })))
t.eq(vim.wo.conceallevel, 2, "a .tex file opened in the same window keeps conceal for VimTeX")
-- diffview's path: the filetype is detected inside nvim_buf_call, away from
-- the window that later shows the buffer.
local hidden = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_call(hidden, function() vim.bo.filetype = "json" end)
vim.cmd("enew")
t.eq(vim.wo.conceallevel, 2, "an ordinary window starts from the global level")
vim.api.nvim_win_set_buf(0, hidden)
t.eq(vim.wo.conceallevel, 0, "and a JSON buffer it is handed later still shows quotes")

-- Diff filler is a hatch, and appending it kept the rest of 'fillchars'.
t.eq(vim.opt.fillchars:get().diff, "╱", "diff filler lines are drawn with ╱")
t.eq(vim.go.fillchars:find("diff:╱", 1, true) ~= nil, true, "the global value carries it")

-- The bytecode loader is on before init.lua's first require, not only from
-- lazy.nvim's bootstrap on.
t.eq(vim.loader.enabled, true, "vim.loader is enabled")
local first_statement
for line in io.lines("init.lua") do
  if not line:match("^%s*%-%-") and line:match("%S") then first_statement = line break end
end
t.eq(first_statement, "vim.loader.enable()", "it is init.lua's first statement")

-- probe.lua and probe.tex may have started lua_ls / texlab.
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
vim.wait(2000, function() return #vim.lsp.get_clients() == 0 end, 20)
vim.fn.delete(root, "rf")

t.done()
