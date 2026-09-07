-- Guards util.cwd: a deleted working directory is recovered into a surviving
-- ancestor with a one-line report, never a traceback (Snacks' dashboard
-- terminal sections hash vim.uv.cwd() at UIEnter and die on nil).
local t = dofile("tests/helper.lua")
local cwd = require("util.cwd")

local root = vim.uv.cwd()
t.ok(root ~= nil, "the suite starts in a real directory")
t.eq(cwd.recover(), nil, "an existing cwd is left alone")
t.eq(vim.uv.cwd(), root, "and not moved")

local saved_pwd = vim.env.PWD

-- Deleted subtree: land in the nearest ancestor that survived, not in ~.
local base = vim.fn.tempname()
local leaf = base .. "/a/b"
vim.fn.mkdir(leaf, "p")
vim.fn.chdir(leaf)
vim.fn.delete(base, "rf")
t.eq(vim.uv.cwd(), nil, "a deleted directory leaves the process without a cwd")
vim.env.PWD = leaf
local report = cwd.recover()
local parent = vim.fn.fnamemodify(base, ":h")
-- realpath: macOS hands out /var/... temp names while getcwd() reports the
-- resolved /private/var/...
t.eq(vim.uv.cwd(), vim.uv.fs_realpath(parent), "recovers into the nearest surviving ancestor")
t.ok(type(report) == "string", "reports what it did")
t.ok(report:find(vim.fn.fnamemodify(leaf, ":~"), 1, true) ~= nil, "the report names the lost directory")
t.ok(report:find(vim.fn.fnamemodify(parent, ":~"), 1, true) ~= nil, "and where it went")
t.ok(not report:find("\n"), "the report is one line")

-- Nothing to work from: home is the fallback.
local base2 = vim.fn.tempname()
vim.fn.mkdir(base2, "p")
vim.fn.chdir(base2)
vim.fn.delete(base2, "d")
vim.env.PWD = nil
cwd.recover()
t.eq(vim.uv.cwd(), vim.uv.os_homedir(), "without $PWD it falls back to home")

vim.env.PWD = saved_pwd
vim.fn.chdir(root)
t.done()
