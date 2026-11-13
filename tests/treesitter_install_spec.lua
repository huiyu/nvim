-- On-demand parser install (plugins/ui/treesitter.lua). A filetype whose parser
-- no list declares installs it on first open, at most once per session, and
-- every buffer waiting on it starts highlighting when the build finishes.
--
-- The branch used to be dead: it tested `pcall(vim.treesitter.language.add)`,
-- whose status is true even for a missing parser since Nvim 0.11 reports that
-- through the return value. Installs are stubbed here, so nothing is built.
local t = dofile("tests/helper.lua")
local nts = require("nvim-treesitter")

local INDENTEXPR = "v:lua.require'nvim-treesitter'.indentexpr()"

local function open(ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = ft
  return buf
end

-- An installed parser attaches directly and requests nothing.
local calls, pending = {}, {}
nts.install = function(langs)
  calls[#calls + 1] = langs
  return { await = function(_, cb) pending[langs[1]] = cb end }
end

local lua_buf = open("lua")
t.ok(vim.treesitter.highlighter.active[lua_buf] ~= nil, "an installed parser highlights on open")
t.eq(vim.bo[lua_buf].indentexpr, INDENTEXPR, "an installed parser sets the indentexpr")
t.eq(#calls, 0, "an installed parser is not reinstalled")

-- Parsers nvim-treesitter can build but this machine has not installed, named
-- like their own filetype so `filetype=` reaches them directly.
local installed = {}
for _, p in ipairs(nts.get_installed("parsers")) do installed[p] = true end
local missing = {}
for _, p in ipairs(nts.get_available()) do
  if not installed[p] and p:match("^%l+$") and vim.treesitter.language.get_lang(p) == p
      and not vim.treesitter.language.add(p) then
    missing[#missing + 1] = p
    if #missing == 3 then break end
  end
end
t.eq(#missing, 3, "three buildable, uninstalled parsers exist to exercise the install path")
local lang, failing, unloadable = missing[1], missing[2], missing[3]

local first = open(lang)
t.eq(calls, { { lang } }, "a missing parser is installed on first open")
local second = open(lang)
t.eq(#calls, 1, "a second buffer does not start another install")
t.ok(vim.treesitter.highlighter.active[first] == nil, "nothing attaches before the parser exists")

-- Finish the build: from here on the parser loads and starts are recorded.
local real_add, real_start = vim.treesitter.language.add, vim.treesitter.start
local started = {}
vim.treesitter.language.add = function(l, ...)
  if l == lang then return true end
  return real_add(l, ...)
end
vim.treesitter.start = function(buf, l) started[buf] = l end
if pending[lang] then pending[lang](nil, true) end
t.ok(vim.wait(1000, function() return started[first] and started[second] end, 10),
  "a finished install attaches every buffer of that language")
t.eq({ vim.bo[first].indentexpr, vim.bo[second].indentexpr }, { INDENTEXPR, INDENTEXPR },
  "a finished install sets the indentexpr")
t.ok(started[lua_buf] == nil, "buffers of other languages are left alone")
vim.treesitter.language.add, vim.treesitter.start = real_add, real_start

-- A failed build is not retried on every FileType for the rest of the session.
open(failing)
t.eq(calls[2], { failing }, "a second missing parser starts its own install")
if pending[failing] then pending[failing]("build failed") end
vim.wait(50)
open(failing)
t.eq(#calls, 2, "a failed install is not retried in the same session")

-- A parser that exists but does not load makes language.add() raise instead
-- of returning nil. Neither the open nor a finished build may surface that as
-- an uncaught error from a scheduled callback.
local notified = {}
local real_notify = vim.notify
vim.notify = function(msg) notified[#notified + 1] = msg end
local function raising(name)
  vim.treesitter.language.add = function(l, ...)
    if l == name then error("Failed to load parser for language '" .. name .. "'") end
    return real_add(l, ...)
  end
end

vim.v.errmsg = ""
open(unloadable)
t.eq(#calls, 3, "a missing parser starts its install")
raising(unloadable)
-- The callback is schedule_wrap'd, and an error raised from a scheduled
-- callback never reaches v:errmsg headless, so run it synchronously here.
local real_schedule, raised = vim.schedule, nil
vim.schedule = function(fn)
  local ok, err = pcall(fn)
  if not ok then raised = err end
end
if pending[unloadable] then pending[unloadable](nil, true) end
vim.schedule = real_schedule
t.eq(raised, nil, "a built parser that does not load raises nothing")

raising("brokenlang")
open("brokenlang")
t.eq(#calls, 3, "an installed parser that does not load is not reinstalled")
t.ok(notified[1] and notified[1]:find(":TSInstall! brokenlang", 1, true) ~= nil,
  "an installed parser that does not load points at a forced rebuild")
t.eq(vim.v.errmsg, "", "an installed parser that does not load raises nothing")
vim.treesitter.language.add, vim.notify = real_add, real_notify

t.done()
