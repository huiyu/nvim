-- Runtime settings for the review loop. The editable defaults live in config;
-- keep our own copy so a caller cannot change them through a returned table.
-- vim.g.ai_review is read afresh on every call. Invalid values warn once per
-- distinct problem and leave their default in place; valid siblings still apply.
local M = {}
local DEFAULTS = vim.deepcopy(require("agent_workbench.review.defaults"))
local warned = {}

local function warn(msg)
  if warned[msg] then return end
  warned[msg] = true
  -- get() may run inside a vim.system callback, where vim.notify is unsafe.
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "AI review" }) end)
end

local function describe(value)
  if value == vim.NIL then return "v:null" end
  if type(value) == "table" then return "a table" end
  return vim.inspect(value)
end

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
  local set, quoted = {}, {}
  for _, value in ipairs(values) do
    set[value] = true
    quoted[#quoted + 1] = ("%q"):format(value)
  end
  return {
    expect = #quoted == 1 and quoted[1] or (table.concat(quoted, ", ", 1, #quoted - 1) .. " or " .. quoted[#quoted]),
    test = function(v) return type(v) == "string" and set[v] == true end,
  }
end

local AGENT = one_of({ "codex" })

-- Only domains live here; all default values come from config.lua. A leaf has
-- a test and the phrase used in its warning. A list also validates each item.
local SCHEMA = {
  retention = { rounds = POSITIVE, saved = POSITIVE },
  max_file_size = integer(1, "a positive integer (bytes)"),
  sources = { codex = BOOLEAN, codecompanion_acp = BOOLEAN, codecompanion_http = BOOLEAN },
  hook_wait_ms = integer(0, "a non-negative integer (milliseconds)"),
  unknown_session = one_of({ "confirm", "refuse" }),
  always_confirm = {
    expect = "a list of " .. AGENT.expect,
    test = function(v) return type(v) == "table" and vim.islist(v) end,
    item = AGENT,
  },
  redirect = BOOLEAN,
  seed_ttl_ms = integer(1, "a positive integer (milliseconds)"),
  history_limit = {
    expect = "a positive integer or false",
    test = function(v) return v == false or POSITIVE.test(v) end,
  },
}

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
    elseif not node.test then
      if type(value) == "table" then
        merge(node, value, out[key], path, overridden)
      else
        warn(("%s should be a table, not %s; using the defaults"):format(where(path), describe(value)))
      end
    elseif not node.test(value) then
      warn(("%s should be %s, not %s; using %s"):format(
        where(path), node.expect, describe(value), vim.inspect(out[key])))
    else
      out[key] = node.item and filter_list(node, value, path) or vim.deepcopy(value)
      overridden[path] = true
    end
  end
end

---@return table effective, table<string, true> overridden
local function resolve()
  local effective, overridden = M.defaults(), {}
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
  return vim.deepcopy(require("agent_workbench.options").get().review or DEFAULTS)
end

---Startup declarations are strict; live vim.g overrides remain leaf-tolerant.
function M.validate(user)
  local function visit(schema, value, prefix)
    assert(type(value) == "table", prefix .. " must be a table")
    for key, item in pairs(value) do
      local path = prefix .. "." .. tostring(key)
      local node = schema[key]
      assert(node, path .. " is not a supported setting")
      if node.test then
        assert(node.test(item), path .. " must be " .. node.expect)
        if node.item then
          for i, entry in ipairs(item) do assert(node.item.test(entry), path .. "[" .. i .. "] must be " .. node.item.expect) end
        end
      else visit(node, item, path) end
    end
  end
  visit(SCHEMA, user, "agent_workbench.review")
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
