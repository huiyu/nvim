-- lua/ai/review/config.lua: the review loop's settings, vim.g.ai_review merged
-- over the defaults on every get().
--
-- What is pinned here: the defaults, a partial and a nested override, a runtime
-- change applying on the next get(), and the rule that an unknown key, a wrong
-- type or a value outside a setting's domain warns once per distinct problem
-- and falls back to the default while the rest of the table still applies.
-- Requiring the module loads no plugin and runs no process.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local WARN = vim.log.levels.WARN

local function loaded_plugins()
  local names = {}
  for name, plugin in pairs(Config.plugins) do
    if plugin._.loaded then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

-- Require it fresh, with every way of starting a process stubbed out, so the
-- assertions cover the module's own load and its first calls.
local spawned = {}
local real = {
  system = vim.system,
  fn_system = vim.fn.system,
  systemlist = vim.fn.systemlist,
  jobstart = vim.fn.jobstart,
  popen = io.popen,
  execute = os.execute,
  spawn = vim.uv.spawn,
}
local function record(name) return function(...) spawned[#spawned + 1] = { name, ... } end end
vim.system, vim.fn.system, vim.fn.systemlist = record("vim.system"), record("system"), record("systemlist")
vim.fn.jobstart, io.popen = record("jobstart"), record("popen")
os.execute, vim.uv.spawn = record("execute"), record("spawn")

local plugins_before = loaded_plugins()
local modules_before = vim.tbl_keys(package.loaded)
local saved_g = vim.g.ai_review
vim.g.ai_review = nil
package.loaded["ai.review.config"] = nil
local config = require("ai.review.config")
config.get()
config.defaults()
config.overrides()

vim.system, vim.fn.system, vim.fn.systemlist = real.system, real.fn_system, real.systemlist
vim.fn.jobstart, io.popen, os.execute, vim.uv.spawn = real.jobstart, real.popen, real.execute, real.spawn

t.eq(loaded_plugins(), plugins_before, "requiring and reading the settings loads no plugin")
t.eq(spawned, {}, "requiring and reading the settings starts no process (no git)")
local new_modules = {}
local known = {}
for _, name in ipairs(modules_before) do known[name] = true end
for name in pairs(package.loaded) do
  if not known[name] and name ~= "ai.review.config" and not name:match("^vim%.") then
    new_modules[#new_modules + 1] = name
  end
end
t.eq(new_modules, {}, "the module requires nothing else")
local source = table.concat(vim.fn.readfile("lua/ai/review/config.lua"), "\n")
t.ok(not source:find("require%s*%(?%s*[\"']"), "the module source has no require")

local notes = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = tostring(msg), level = level, title = opts and opts.title }
end
-- Warnings are scheduled (vim.notify cannot run in a fast event); let them land.
local function warnings()
  vim.wait(20, function() return false end)
  local out = notes
  notes = {}
  return out
end

local DEFAULTS = {
  retention = { rounds = 20, saved = 10 },
  max_file_size = 10 * 1024 * 1024,
  sources = { claude = true, codex = true, codecompanion_acp = true, codecompanion_http = true },
  hook_wait_ms = 2500,
  claude_cwd = "git_root",
  unknown_session = "confirm",
  always_confirm = {},
  redirect = true,
  history_limit = 100,
}
local function with(overrides) return vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), overrides) end

-- Defaults ---------------------------------------------------------------

vim.g.ai_review = nil
t.eq(config.get(), DEFAULTS, "without vim.g.ai_review, get() is the §10.7 defaults")
t.eq(config.defaults(), DEFAULTS, "defaults() is the same table")
t.eq(config.overrides(), {}, "nothing is overridden")
vim.g.ai_review = {}
t.eq(config.get(), DEFAULTS, "an empty vim.g.ai_review is the defaults")

local copy = config.defaults()
copy.retention.rounds, copy.always_confirm[1] = 1, "codex"
local got = config.get()
got.sources.claude = false
t.eq(config.defaults(), DEFAULTS, "defaults() is a deep copy: changing it leaves the next one alone")
t.eq(config.get(), DEFAULTS, "get() is a fresh table: changing it leaves the next one alone")
t.eq(warnings(), {}, "the defaults raise no warning")

-- Overrides --------------------------------------------------------------

vim.g.ai_review = { claude_cwd = "cwd", sources = { codex = false }, always_confirm = { "codex" } }
t.eq(config.get(), with({ claude_cwd = "cwd", sources = { codex = false }, always_confirm = { "codex" } }),
  "a partial override changes only the keys it names; sibling sources stay true")
t.eq(config.overrides(), { claude_cwd = true, ["sources.codex"] = true, always_confirm = true },
  "overrides() names each key that came from vim.g.ai_review")

vim.g.ai_review = { retention = { rounds = 30 } }
local nested = config.get()
t.eq(nested.retention, { rounds = 30, saved = 10 }, "retention.rounds alone keeps retention.saved at its default")
t.eq(nested, with({ retention = { rounds = 30 } }), "a nested override touches nothing else")
t.eq(config.overrides(), { ["retention.rounds"] = true }, "overrides() names the nested key by its dotted path")

vim.g.ai_review = { history_limit = false, redirect = false, hook_wait_ms = 0 }
local falsy = config.get()
t.eq({ falsy.history_limit, falsy.redirect, falsy.hook_wait_ms }, { false, false, 0 },
  "false and 0 are values, not a missing key")

-- A list replaces the default; it is not merged entry by entry.
vim.g.ai_review = { always_confirm = { "claude", "codex" } }
t.eq(config.get().always_confirm, { "claude", "codex" }, "always_confirm takes the user's list")

-- Vimscript spelling reaches the same table.
vim.cmd([[let g:ai_review = {'retention': {'saved': 3}, 'unknown_session': 'refuse', 'redirect': v:false}]])
t.eq(config.get(), with({ retention = { saved = 3 }, unknown_session = "refuse", redirect = false }),
  "a Vimscript dict with v:false works the same")
t.eq(warnings(), {}, "valid overrides raise no warning")

-- Runtime changes --------------------------------------------------------

vim.g.ai_review = { hook_wait_ms = 1000 }
t.eq(config.get().hook_wait_ms, 1000, "a value set at runtime is read by the next get()")
vim.g.ai_review = { hook_wait_ms = 500 }
t.eq(config.get().hook_wait_ms, 500, "changing it again takes effect at once")
vim.g.ai_review = nil
t.eq(config.get().hook_wait_ms, 2500, "unsetting vim.g.ai_review restores the default")

-- Bad input: warn once per distinct problem, fall back, keep the rest -----

local function bad(case)
  vim.g.ai_review = case.input
  local effective = config.get()
  t.eq(effective, case.want, case.what .. ": the bad value falls back to its default, the rest applies")
  local first = warnings()
  t.eq(#first, 1, case.what .. ": warns once")
  local note = first[1] or {}
  t.ok(note.level == WARN and note.title == "AI review", case.what .. ": WARN titled AI review")
  -- Compared through t.eq so a failure prints the actual message.
  local msg = tostring(note.msg)
  t.eq(msg:find(case.mentions, 1, true) and case.mentions or msg, case.mentions,
    case.what .. ": the warning names the problem")
  config.get()
  config.overrides()
  t.eq(warnings(), {}, case.what .. ": the same problem does not warn again")
  t.eq(config.overrides(), case.overrides or {}, case.what .. ": overrides() lists only what took effect")
end

bad({
  what = "unknown top-level key",
  input = { retension = { rounds = 5 } },
  want = DEFAULTS,
  mentions = "vim.g.ai_review.retension is not a setting",
})
bad({
  what = "unknown nested key",
  input = { retention = { round = 5 } },
  want = DEFAULTS,
  mentions = "vim.g.ai_review.retention.round is not a setting; ignored (known: rounds, saved)",
})
bad({
  what = "wrong type for a setting",
  input = { retention = { rounds = "30" } },
  want = DEFAULTS,
  mentions = 'retention.rounds should be a positive integer, not "30"; using 20',
})
bad({
  what = "wrong type for a group",
  input = { sources = false },
  want = DEFAULTS,
  mentions = "vim.g.ai_review.sources should be a table, not false",
})
bad({
  what = "wrong type for a boolean",
  input = { sources = { claude = 1 } },
  want = DEFAULTS,
  mentions = "sources.claude should be a boolean, not 1",
})
bad({
  what = "out-of-enum value",
  input = { claude_cwd = "home" },
  want = DEFAULTS,
  mentions = 'claude_cwd should be "git_root" or "cwd", not "home"; using "git_root"',
})
bad({
  what = "out-of-enum unknown_session",
  input = { unknown_session = "allow" },
  want = DEFAULTS,
  mentions = 'unknown_session should be "confirm" or "refuse"',
})
bad({
  what = "zero where a positive integer is required",
  input = { retention = { saved = 0 } },
  want = DEFAULTS,
  mentions = "retention.saved should be a positive integer, not 0; using 10",
})
bad({
  what = "fractional byte count",
  input = { max_file_size = 1.5 },
  want = DEFAULTS,
  mentions = "max_file_size should be a positive integer (bytes), not 1.5",
})
bad({
  what = "negative wait",
  input = { hook_wait_ms = -1 },
  want = DEFAULTS,
  mentions = "hook_wait_ms should be a non-negative integer (milliseconds), not -1",
})
bad({
  what = "true where only false or a count is allowed",
  input = { history_limit = true },
  want = DEFAULTS,
  mentions = "history_limit should be a positive integer or false, not true",
})
bad({
  what = "always_confirm that is not a list",
  input = { always_confirm = "codex" },
  want = DEFAULTS,
  mentions = 'always_confirm should be a list of "claude" or "codex", not "codex"; using {}',
})
bad({
  what = "vim.g.ai_review that is not a table",
  input = "cwd",
  want = DEFAULTS,
  mentions = 'vim.g.ai_review should be a table, not "cwd"; using the defaults',
})
-- A bad entry in always_confirm is dropped on its own: falling back to {} would
-- silently remove the confirmations the valid entries asked for.
bad({
  what = "unknown agent in always_confirm",
  input = { always_confirm = { "codex", "claud" } },
  want = with({ always_confirm = { "codex" } }),
  mentions = 'vim.g.ai_review.always_confirm[2] should be "claude" or "codex", not "claud"; ignored',
  overrides = { always_confirm = true },
})
-- One bad key leaves its valid siblings in effect.
bad({
  what = "a bad key beside good ones",
  input = { retention = { rounds = 30, saved = -2 }, claude_cwd = "cwd" },
  want = with({ retention = { rounds = 30 }, claude_cwd = "cwd" }),
  mentions = "retention.saved should be a positive integer, not -2",
  overrides = { ["retention.rounds"] = true, claude_cwd = true },
})

-- Distinct problems are counted apart, and a fixed value stops warning.
vim.g.ai_review = { claude_cwd = "home", unknown_session = "allow", retention = { rounds = "30" } }
config.get()
t.eq(warnings(), {}, "problems already reported stay quiet when they come back together")
vim.g.ai_review = { claude_cwd = "nowhere" }
config.get()
t.eq(#warnings(), 1, "another bad value for the same key is a new problem and warns")
vim.g.ai_review = { claude_cwd = "cwd" }
t.eq(config.get().claude_cwd, "cwd", "once fixed, the value applies")
t.eq(warnings(), {}, "and nothing warns")

-- util.baseline chains vim.system callbacks, fast events where vim.notify is
-- not allowed; a setting read there still works and its warning still arrives.
vim.g.ai_review = { retention = { rounds = 7 }, hook_wait_ms = "soon" }
local result
real.system({ "true" }, {}, function()
  local ok, value = pcall(config.get)
  result = { fast = vim.in_fast_event(), ok = ok }
  if ok then result.rounds, result.wait = value.retention.rounds, value.hook_wait_ms end
end)
vim.wait(5000, function() return result ~= nil end, 10)
t.eq(result, { fast = true, ok = true, rounds = 7, wait = 2500 }, "get() works inside a vim.system callback")
local fast_notes = warnings()
t.ok(#fast_notes == 1 and fast_notes[1].msg:find("hook_wait_ms", 1, true) ~= nil,
  "a warning raised in a fast event is delivered once the loop is free")

vim.notify = real_notify
vim.g.ai_review = saved_g
t.done()
