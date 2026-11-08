-- :AI -- switch the provider or the HTTP key profile without restarting Nvim.
--
-- A switch changes state (lua/ai/config.lua), mapping descriptions and
-- CodeCompanion's live defaults, nothing else: it never starts, stops, shows or
-- hides a native terminal, an ACP connection or a chat. What already exists
-- keeps the provider and adapter it was created with; the switch decides what
-- the next new one uses. The one-panel-per-tabpage rule applies later, when a
-- key reveals the active provider's panel (lua/ai/init.lua, make_room).

local M = {}

local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local function notify(msg, level)
  vim.notify(msg, level or INFO, { title = "AI" })
end

local function config() return require("ai.config") end

local function is_set(var) return (vim.env[var] or "") ~= "" end

local function changed(axis, from, to)
  require("ai").apply_keymaps()
  -- CodeCompanion's live defaults; a no-op until it has loaded.
  require("ai.companion").sync()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "AIStateChanged",
    modeline = false,
    data = { axis = axis, from = from, to = to },
  })
end

---@param name string? nil opens the provider picker
function M.provider(name)
  if not name then return M.pick("provider") end
  local c = config()
  local from = c.provider
  if name:lower() == from then return notify(c.label .. " is already the AI provider") end
  local ok, err = pcall(c.use_provider, name)
  if not ok then return notify(err, ERROR) end
  changed("provider", from, c.provider)

  local old = require("ai.backend." .. from)
  local still = old.running and old.running()
    and (" · %s keeps running"):format(c.providers[from].label) or ""
  notify(("AI provider: %s (API: %s)%s"):format(c.label, c.key.label, still))
end

---@param name string? nil opens the key picker
function M.key(name)
  if not name then return M.pick("key") end
  local c = config()
  local from = c.key_setting()
  if name:lower() == from then return notify(("%s is already the API key profile"):format(from)) end
  local ok, err = pcall(c.use_key, name)
  if not ok then return notify(err, ERROR) end
  changed("key", from, c.key_setting())

  local how = c.key.auto and ("auto → %s"):format(c.key.label) or c.key.label
  notify(("AI key: %s (%s)"):format(how, c.codecompanion.api_key))
  -- Still switched: the variable may be exported later, and the choice is
  -- about which key, not whether one is present yet.
  if not is_set(c.codecompanion.api_key) then
    notify(("%s is not set — API chat and inline edits refuse to start until it is")
      :format(c.codecompanion.api_key), WARN)
  end
end

---Pad to a display width, so labels with non-ASCII arrows still line up.
local function pad(text, width)
  return text .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(text), 0))
end

local function key_status(var)
  return ("%s %s"):format(var, is_set(var) and "✓" or "✗ not set")
end

---Pick a provider or a key profile with vim.ui.select (Snacks renders it).
---@param axis "provider"|"key"|nil nil lists both axes
function M.pick(axis)
  local c = config()
  local items = {}
  if axis ~= "key" then
    for _, name in ipairs(c.names()) do
      local current = name == c.provider
      items[#items + 1] = {
        axis = "provider", name = name, current = current,
        text = c.providers[name].label,
        detail = current and "native terminal + ACP chat · subscription" or "",
      }
    end
  end
  if axis ~= "provider" then
    local auto_target = c.key_profiles[c.providers[c.provider].key_profile]
    items[#items + 1] = {
      axis = "key", name = "auto", current = c.key.auto,
      text = "auto → " .. auto_target.label, detail = key_status(auto_target.api_key),
    }
    for _, name in ipairs(c.key_names()) do
      local p = c.key_profiles[name]
      items[#items + 1] = {
        axis = "key", name = name, current = not c.key.auto and c.key.name == name,
        text = p.label, detail = key_status(p.api_key),
      }
    end
  end

  local width = 0
  for _, item in ipairs(items) do width = math.max(width, vim.fn.strdisplaywidth(item.text)) end
  vim.ui.select(items, {
    prompt = "AI provider / API key",
    format_item = function(item)
      return ("%s%s %s%s"):format(pad(item.axis == "provider" and "Provider" or "Key", 10),
        item.current and "●" or "○", pad(item.text, width + 2), item.detail)
    end,
  }, function(choice)
    if not choice or choice.current then return end
    if choice.axis == "provider" then M.provider(choice.name) else M.key(choice.name) end
  end)
end

---Summarise both axes, the keys and the native agents. Loads no plugin.
function M.info()
  local c, info = config(), require("ai").info()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end

  local provider_note = info.provider ~= info.startup.provider
    and (" (started as %s)"):format(c.providers[info.startup.provider].label) or ""
  add("Provider  %s%s", info.label, provider_note)
  add("          native %s · ACP %s", info.native, info.codecompanion.chat)

  local key_now = c.key_setting()
  local key_note = key_now ~= info.startup.key and (" (started as %s)"):format(info.startup.key) or ""
  add("Key       %s · %s%s", info.key.label, info.key.auto and "auto" or "pinned", key_note)
  add("          HTTP %s", info.codecompanion.inline)

  local width = 0
  for name in pairs(info.profiles) do width = math.max(width, #name) end
  for i, name in ipairs(c.key_names()) do
    local p = info.profiles[name]
    add("%s%s  %s %s", i == 1 and "Profiles  " or "          ", pad(name, width), p.var,
      p.set and "set" or "not set")
  end

  local cli = {}
  for _, var in ipairs(vim.tbl_keys(info.cli_keys)) do
    cli[#cli + 1] = ("%s %s"):format(var, info.cli_keys[var] and "SET (bills the API)" or "not set")
  end
  table.sort(cli)
  add("CLI keys  %s", table.concat(cli, " · "))

  local agents = {}
  for _, name in ipairs(c.names()) do
    local s = info.sessions[name]
    local state = not s.running and "not started" or (s.visible and "visible here" or "running, not shown here")
    agents[#agents + 1] = ("%s: %s"):format(s.label, state)
  end
  add("Agents    %s", table.concat(agents, " · "))

  if info.chats then
    local chats = {}
    for name, n in pairs(info.chats) do chats[#chats + 1] = ("%s ×%d"):format(name, n) end
    table.sort(chats)
    add("Chats     %s", #chats > 0 and table.concat(chats, " · ") or "none")
  end

  notify(table.concat(lines, "\n"))
end

local function complete(arglead, cmdline)
  local c = config()
  local args = vim.split(cmdline, "%s+", { trimempty = true })
  -- How many words are complete; the one being typed is not.
  local n = #args - (cmdline:match("%s$") and 0 or 1)
  local words = {}
  if n <= 1 then
    words = { "provider", "key", "info" }
  elseif n == 2 and args[2] == "provider" then
    words = c.names()
  elseif n == 2 and args[2] == "key" then
    words = vim.list_extend({ "auto" }, c.key_names())
  end
  return vim.tbl_filter(function(w) return vim.startswith(w, arglead) end, words)
end

function M.setup()
  vim.api.nvim_create_user_command("AI", function(o)
    local sub, arg = o.fargs[1], o.fargs[2]
    if not sub then return M.pick() end
    if #o.fargs <= 2 then
      if sub == "provider" then return M.provider(arg) end
      if sub == "key" then return M.key(arg) end
      if sub == "info" and not arg then return M.info() end
    end
    notify("Usage: :AI [provider [name] | key [name] | info]", ERROR)
  end, { nargs = "*", complete = complete, desc = "Switch the AI provider / API key profile" })

  vim.api.nvim_create_user_command("AIInfo", function() M.info() end,
    { desc = "Show the AI provider, key profile and native agents" })
end

return M
