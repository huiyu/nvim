-- :AI -- the open chats, a new chat, and the HTTP key profile.
--
--   :AI             switch to another open chat (<leader>al)
--   :AI new         start a chat on any available backend (<leader>an)
--   :AI key [name]  the key profile inline edits and command prompts use
--                   (<leader>ax): `auto`, which follows the default backend,
--                   or a profile name, which pins it
--   :AI info        the default backend, the key, and where every open chat
--                   is (also :AIInfo)
--
-- The default backend is fixed at startup (lua/ai/config.lua), so there is no
-- `:AI provider` any more: a new chat names its backend in the picker. A key
-- switch changes state, <leader>ae's description and CodeCompanion's inline and
-- command adapters, nothing else: no chat, terminal or ACP connection starts,
-- stops, shows or hides, and a chat keeps the adapter it was created with.

local M = {}

local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local function notify(msg, level)
  vim.notify(msg, level or INFO, { title = "AI" })
end

local function config() return require("ai.config") end

local function is_set(var) return (vim.env[var] or "") ~= "" end

---@param name string? nil opens the key picker
function M.key(name)
  if not name then return M.pick() end
  local c = config()
  local from = c.key_setting()
  if name:lower() == from then return notify(("%s is already the API key profile"):format(from)) end
  local ok, err = pcall(c.use_key, name)
  if not ok then return notify(err, ERROR) end
  require("ai").apply_keymaps()
  -- CodeCompanion's live inline/cmd adapters; a no-op until it has loaded.
  require("ai.companion").sync()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "AIStateChanged",
    modeline = false,
    data = { axis = "key", from = from, to = c.key_setting() },
  })

  local how = c.key.auto and ("auto → %s"):format(c.key.label) or c.key.label
  notify(("AI key: %s (%s)"):format(how, c.codecompanion.api_key))
  -- Still switched: the variable may be exported later, and the choice is
  -- about which key, not whether one is present yet.
  if not is_set(c.codecompanion.api_key) then
    notify(("%s is not set — inline edits and command prompts refuse until it is")
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

---Pick a key profile with vim.ui.select (Snacks renders it): `auto` first,
---then every profile.
function M.pick()
  local c = config()
  local auto_target = c.key_profiles[c.providers[c.default].key_profile]
  local items = { {
    name = "auto", current = c.key.auto,
    text = "auto → " .. auto_target.label, detail = key_status(auto_target.api_key),
  } }
  for _, name in ipairs(c.key_names()) do
    local p = c.key_profiles[name]
    items[#items + 1] = {
      name = name, current = not c.key.auto and c.key.name == name,
      text = p.label, detail = key_status(p.api_key),
    }
  end

  local width = 0
  for _, item in ipairs(items) do width = math.max(width, vim.fn.strdisplaywidth(item.text)) end
  vim.ui.select(items, {
    prompt = "API key profile (inline edits, command prompts)",
    kind = "ai_key",
    format_item = function(item)
      return ("%s %s%s"):format(item.current and "●" or "○", pad(item.text, width + 2), item.detail)
    end,
  }, function(choice)
    if not choice or choice.current then return end
    M.key(choice.name)
  end)
end

---Summarise the default backend, the key, and where every open chat is.
---Loads no plugin.
function M.info()
  local c, info = config(), require("ai").info()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end

  local source = info.default_source == "built-in" and "built-in default"
    or ("%s=%s"):format(info.default_source, info.default)
  add("Default   %s (%s) · fixed at startup", info.default_label, source)
  add("          first in :AI new · CodeCompanion's own chats on %s", info.codecompanion.chat)

  add("Key       %s · %s", info.key.label, info.key.auto and "auto (follows the default)" or "pinned")
  add("          inline and command prompts on %s", info.codecompanion.inline)

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

  if #info.chats == 0 then
    add("Chats     none open")
  else
    for i, chat in ipairs(info.chats) do
      add("%s%s · %s", i == 1 and "Chats     " or "          ", chat.label, chat.where)
    end
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
    words = { "new", "key", "info" }
  elseif n == 2 and args[2] == "key" then
    words = vim.list_extend({ "auto" }, c.key_names())
  end
  return vim.tbl_filter(function(w) return vim.startswith(w, arglead) end, words)
end

function M.setup()
  vim.api.nvim_create_user_command("AI", function(o)
    local sub, arg = o.fargs[1], o.fargs[2]
    -- The chat pickers of <leader>al / <leader>an (lua/ai/slot.lua).
    if not sub then return require("ai").switch_chat() end
    if sub == "provider" then
      return notify(":AI provider is gone: :AI new (<leader>an) picks the backend of each new chat;"
        .. " the default is set at startup (vi --claude / vi --codex)", ERROR)
    end
    if #o.fargs <= 2 then
      if sub == "key" then return M.key(arg) end
      if sub == "info" and not arg then return M.info() end
      if sub == "new" and not arg then return require("ai").new_chat() end
    end
    notify("Usage: :AI [new | key [name] | info]", ERROR)
  end, { nargs = "*", complete = complete, desc = "Switch AI chat, start one, or set the API key profile" })

  vim.api.nvim_create_user_command("AIInfo", function() M.info() end,
    { desc = "Show the default AI backend, the key profile and the open chats" })
end

return M
