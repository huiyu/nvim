local t = dofile("tests/helper.lua")

-- `:checkhealth config` gates the tree-sitter CLI on nvim-treesitter's own
-- floor: main builds every parser with `tree-sitter build`, so a missing or
-- older CLI means no parser installs or updates. Stand-in executables on PATH
-- play each case; the report is collected by replacing vim.health's writers.
local messages = {}
local writers = {}
for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
  writers[level] = vim.health[level]
  vim.health[level] = function(msg) messages[#messages + 1] = { level = level, msg = msg } end
end

local function fake_cli(output)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local exe = dir .. "/tree-sitter"
  vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' " .. vim.fn.shellescape(output) }, exe)
  vim.fn.setfperm(exe, "rwxr-xr-x")
  return dir
end

---@param path string the PATH to run the check under
---@return { level: string, msg: string }?
local function tree_sitter_line(path)
  local saved = vim.env.PATH
  vim.env.PATH = path
  messages = {}
  local ok, err = pcall(require("config.health").check)
  vim.env.PATH = saved
  t.ok(ok, "the health check runs to completion" .. (ok and "" or (": " .. tostring(err))))
  for _, m in ipairs(messages) do
    if m.msg:find("^tree%-sitter") then return m end
  end
end

-- /usr/bin and /bin hold no tree-sitter on macOS or the CI image.
local base = "/usr/bin:/bin"

local floor = tree_sitter_line(fake_cli("tree-sitter 0.26.1") .. ":" .. base)
t.eq(floor and floor.level, "ok", "the documented floor passes")
t.ok(floor and floor.msg:find("0.26.1", 1, true), "the found version is reported")

local newer = tree_sitter_line(fake_cli("tree-sitter 0.27.2 (abcdef012345)") .. ":" .. base)
t.eq(newer and newer.level, "ok", "a newer CLI passes")

local old = tree_sitter_line(fake_cli("tree-sitter 0.25.10") .. ":" .. base)
t.eq(old and old.level, "error", "a CLI below the floor is an error")
t.ok(old and old.msg:find("needs 0.26.1", 1, true), "the error names the floor")

local garbled = tree_sitter_line(fake_cli("no version here") .. ":" .. base)
t.eq(garbled and garbled.level, "error", "an unreadable version is not taken as good enough")

local missing = tree_sitter_line(base)
t.eq(missing and missing.level, "error", "a missing CLI is an error")
t.ok(missing and missing.msg:find("not found", 1, true), "the error says it is not found")

for level, fn in pairs(writers) do vim.health[level] = fn end
t.done()
