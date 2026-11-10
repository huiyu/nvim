-- Settings for the agent review loop: every tunable's default lives here, and a
-- user overrides only the ones they care about, from init.lua:
--
--   vim.g.ai_review = { retention = { rounds = 30 }, claude_cwd = "cwd" }
--
-- get() merges vim.g.ai_review over the defaults on every call, so a change at
-- runtime applies from the next use on. Change it by assigning a whole table:
-- vim.g hands out copies, so `vim.g.ai_review.retention.rounds = 30` is lost.
--
-- A key that is not a setting, a value of the wrong type and a value outside a
-- setting's domain each warn once per distinct problem and fall back to the
-- default; the rest of the table still applies. This module requires nothing
-- and runs no git, so any module can read it at startup. get() also works
-- inside a vim.system callback: the warnings are scheduled, because
-- vim.notify must not run in a fast event.

local M = {}

-- The native agents, as always_confirm names them.
local AGENTS = { "claude", "codex" }

local warned = {}

local function warn(msg)
  if warned[msg] then return end
  warned[msg] = true
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "AI review" }) end)
end

local function describe(value)
  if value == vim.NIL then return "v:null" end
  if type(value) == "table" then return "a table" end
  return vim.inspect(value)
end

---@param words string[]
---@return string `"a", "b" or "c"`
local function either(words)
  local quoted = vim.tbl_map(function(w) return ("%q"):format(w) end, words)
  if #quoted == 1 then return quoted[1] end
  return table.concat(quoted, ", ", 1, #quoted - 1) .. " or " .. quoted[#quoted]
end

-- A validator is { expect = <phrase for the warning>, test = fn(value) -> ok },
-- plus `item` (another validator) for a list whose entries are checked one by
-- one: a bad entry is dropped on its own, the rest of the list still applies.

local function integer(min, expect)
  return {
    expect = expect,
    test = function(v)
      return type(v) == "number" and v >= min and v < math.huge and v == math.floor(v)
    end,
  }
end

local POSITIVE = integer(1, "a positive integer")
local BOOLEAN = { expect = "a boolean", test = function(v) return type(v) == "boolean" end }

local function one_of(values)
  local set = {}
  for _, v in ipairs(values) do set[v] = true end
  return { expect = either(values), test = function(v) return type(v) == "string" and set[v] == true end }
end

local function list_of(item)
  return {
    expect = "a list of " .. item.expect,
    item = item,
    test = function(v) return type(v) == "table" and vim.islist(v) end,
  }
end

local function setting(default, validator)
  return { default = default, validator = validator }
end

local function is_setting(node) return node.validator ~= nil end

-- Every setting with its default and domain; the comments say what each one
-- controls.
local SCHEMA = {
  retention = {
    -- Newest round baselines kept per worktree (util.baseline prune). A round
    -- with a non-empty feedback draft is never pruned.
    rounds = setting(20, POSITIVE),
    -- Newest saved baselines (<leader>gK) kept per worktree.
    saved = setting(10, POSITIVE),
  },
  -- Untracked files larger than this many bytes are left out of a snapshot by
  -- an exclude pathspec, so they are never hashed into .git/objects.
  max_file_size = setting(10 * 1024 * 1024, integer(1, "a positive integer (bytes)")),
  -- false: that source never opens a round. For the native agents no hook is
  -- injected; for CodeCompanion no on_before_submit callback is added.
  sources = {
    claude = setting(true, BOOLEAN),
    codex = setting(true, BOOLEAN),
    codecompanion_acp = setting(true, BOOLEAN),
    codecompanion_http = setting(true, BOOLEAN),
  },
  -- How long scripts/agent-hook and CodeCompanion's on_before_submit wait for
  -- the baseline before letting the prompt through. 0 never waits.
  hook_wait_ms = setting(2500, integer(0, "a non-negative integer (milliseconds)")),
  -- Where native Claude starts: the current file's Git root, as Codex does, or
  -- Nvim's working directory (the earlier behaviour).
  claude_cwd = setting("git_root", one_of({ "git_root", "cwd" })),
  -- A native session that cannot be confirmed before delivery: ask, or refuse.
  unknown_session = setting("confirm", one_of({ "confirm", "refuse" })),
  -- Agents whose delivery is confirmed every time, even when the session is
  -- known, e.g. { "codex" }.
  always_confirm = setting({}, list_of(one_of(AGENTS))),
  -- false: when a round's owner is gone, refuse without offering "send to the
  -- current session".
  redirect = setting(true, BOOLEAN),
  -- How long a native agent has to open its prompt editor for a delivered
  -- feedback draft before the delivery counts as failed and the draft is kept.
  seed_ttl_ms = setting(10000, integer(1, "a positive integer (milliseconds)")),
  -- How many commits <leader>gH/<leader>gV hand to :CodeDiff history; false
  -- lifts the limit.
  history_limit = setting(100, {
    expect = "a positive integer or false",
    test = function(v) return v == false or POSITIVE.test(v) end,
  }),
}

local function collect_defaults(schema)
  local out = {}
  for key, node in pairs(schema) do
    if is_setting(node) then
      out[key] = vim.deepcopy(node.default)
    else
      out[key] = collect_defaults(node)
    end
  end
  return out
end

local DEFAULTS = collect_defaults(SCHEMA)

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- "retention.rounds", or "always_confirm[2]" for a list entry. The overrides
-- set is keyed by this form; warnings prefix it with vim.g.ai_review.
local function join(prefix, key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") then
    return prefix == "" and key or prefix .. "." .. key
  end
  return ("%s[%s]"):format(prefix, vim.inspect(key))
end

local function where(path)
  return "vim.g.ai_review" .. ((path == "" or path:sub(1, 1) == "[") and path or "." .. path)
end

-- Drop each bad entry with a warning of its own; keep the rest in order.
local function filter_list(validator, list, path)
  local kept = {}
  for i, entry in ipairs(list) do
    if validator.item.test(entry) then
      kept[#kept + 1] = entry
    else
      warn(("%s should be %s, not %s; ignored"):format(where(join(path, i)), validator.item.expect, describe(entry)))
    end
  end
  return kept
end

local function merge(schema, user, out, prefix, overridden)
  for _, key in ipairs(sorted_keys(user)) do
    local value = user[key]
    local node = type(key) == "string" and schema[key] or nil
    local path = join(prefix, key)
    if not node then
      warn(("%s is not a setting; ignored (known: %s)"):format(where(path), table.concat(sorted_keys(schema), ", ")))
    elseif not is_setting(node) then
      if type(value) == "table" then
        merge(node, value, out[key], path, overridden)
      else
        warn(("%s should be a table, not %s; using the defaults"):format(where(path), describe(value)))
      end
    elseif not node.validator.test(value) then
      warn(("%s should be %s, not %s; using %s"):format(
        where(path), node.validator.expect, describe(value), vim.inspect(node.default)))
    else
      out[key] = node.validator.item and filter_list(node.validator, value, path) or vim.deepcopy(value)
      overridden[path] = true
    end
  end
end

---@return table effective, table<string, true> overridden
local function resolve()
  local effective, overridden = vim.deepcopy(DEFAULTS), {}
  local user = vim.g.ai_review
  if user == nil then return effective, overridden end
  if type(user) ~= "table" then
    warn(("vim.g.ai_review should be a table, not %s; using the defaults"):format(describe(user)))
    return effective, overridden
  end
  merge(SCHEMA, user, effective, "", overridden)
  return effective, overridden
end

---The effective settings: vim.g.ai_review merged over the defaults, read now.
---A fresh table on every call, so a caller may keep or change it freely.
---@return table
function M.get()
  return (resolve())
end

---The defaults alone, as a fresh deep copy.
---@return table
function M.defaults()
  return vim.deepcopy(DEFAULTS)
end

---Which settings currently come from vim.g.ai_review, keyed by dotted path
---(`{ ["retention.rounds"] = true }`). A rejected value is not an override: it
---fell back to the default.
---@return table<string, true>
function M.overrides()
  local _, overridden = resolve()
  return overridden
end

return M
