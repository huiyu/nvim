-- CodeCompanion's two chat kinds, aimed by the facade's <leader>a keys
-- (lua/ai/init.lua):
--
--   acp   agent chat  the active provider's agent over ACP, on the subscription
--   http  API chat    the active key profile over HTTP, on API credits
--
-- Upstream's Toggle and Add only know `last_chat`, whatever its kind, so a
-- toggle could surface an API chat when an agent chat was asked for. This
-- module picks the chat of the asked-for kind itself and hands it to upstream's
-- own single-slot open, so the two kinds still share one chat window.
--
-- That reaches into CodeCompanion's chat internals: `chat.adapter`, `chat.ui`
-- (is_visible / is_visible_non_curtab / hide / winnr), `chat.prompt:add`,
-- `interactions.chat.open` and `utils.context.get`. The facade pcall-wraps
-- toggle and add and falls back to the upstream commands with a WARN, and
-- tests/companion_spec.lua pins the behaviour.
--
-- Nothing here requires CodeCompanion at the top level. The first call that
-- needs it does, and lazy's module autoload loads the plugin then -- so the
-- keys can be defined at startup without loading anything.

local config = require("ai.config")

local M = {}

local ERROR, WARN = vim.log.levels.ERROR, vim.log.levels.WARN

---@alias ai.CompanionKind "acp"|"http"

---Has CodeCompanion loaded? Before it has, no chat can exist, so nothing needs
---to load it to find out.
local function loaded()
  local plugin = require("lazy.core.config").plugins["codecompanion.nvim"]
  return plugin ~= nil and plugin._.loaded ~= nil
end

---The CodeCompanion adapter a new chat of `kind` gets in the current state.
---@param kind ai.CompanionKind
---@return string
function M.adapter_name(kind)
  return kind == "acp" and config.codecompanion.acp_adapter or config.codecompanion.http_adapter
end

---Refuse before CodeCompanion turns a missing key into a 401, or a missing ACP
---bridge into an asynchronous connection error. Only what starts something is
---checked here: creating a chat (an agent chat spawns its bridge at once, an
---API chat may fetch the model list with the key) and the inline prompt.
---@param kind ai.CompanionKind
---@return boolean ok
function M.preflight(kind)
  local problem
  if kind == "http" then
    local var = config.codecompanion.api_key
    if (vim.env[var] or "") == "" then
      problem = ("%s is not set\nnothing sent: export it, or :AI key <profile>"):format(var)
    end
  else
    local bridge = config.codecompanion.acp_command
    if vim.fn.executable(bridge) ~= 1 then
      problem = ("%s not found — no agent chat\nsee :checkhealth config"):format(bridge)
    end
  end
  if problem then
    -- Two short lines: the notifier cuts a long one off at its width.
    -- Scheduled: <leader>ae asks from an expr mapping, under textlock, where
    -- opening the notifier's float is not allowed.
    vim.schedule(function() vim.notify(problem, ERROR, { title = "AI" }) end)
  end
  return problem == nil
end

---Is the chat on screen in this tabpage?
local function here(chat)
  return chat.ui:is_visible() and not chat.ui:is_visible_non_curtab()
end

---Compare two rank tuples, most significant field first.
local function outranks(a, b)
  if not b then return true end
  for i = 1, #a do
    if a[i] ~= b[i] then return a[i] > b[i] end
  end
  return false
end

---The chat of `kind` on that kind's current adapter, if any: the one on
---screen in this tabpage first, then upstream's last chat, then the most
---recently entered. `lastused` only has a resolution of seconds, so the buffer number
---(newer chats get higher ones) breaks the remaining ties.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.find(kind)
  if not loaded() then return nil end
  local want = M.adapter_name(kind)
  local last = require("codecompanion").last_chat()
  local best, best_rank
  for _, entry in ipairs(require("codecompanion").buf_get_chat()) do
    local chat = entry.chat
    local adapter = chat and chat.adapter
    if adapter and adapter.type == kind and adapter.name == want and vim.api.nvim_buf_is_valid(chat.bufnr) then
      local info = vim.fn.getbufinfo(chat.bufnr)[1] or {}
      local rank = { here(chat) and 1 or 0, chat == last and 1 or 0, info.lastused or 0, chat.bufnr }
      if outranks(rank, best_rank) then best, best_rank = chat, rank end
    end
  end
  return best
end

local function focus(chat)
  local win = chat and chat.ui.winnr
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
    vim.api.nvim_set_current_win(win)
  end
end

---Put `chat` on screen here through upstream's single-slot open
---(interactions/chat/init.lua, Chat.open): the chat this tabpage shows hands
---over its window, so agent and API chats share one panel.
---@param toggled boolean? keep the cursor where it was left, as a toggle does
local function show(chat, toggled)
  -- One chat has one window. Shown in another tabpage it moves here, as
  -- :CodeCompanionChat Toggle moves it; ui:open would otherwise see it
  -- "visible" and open nothing.
  if chat.ui:is_visible_non_curtab() then chat.ui:hide() end
  require("codecompanion.interactions.chat").open({ ui = chat.ui, toggled = toggled })
  focus(chat)
end

---Start a chat of `kind` on the current adapter (and the profile's model).
---@param kind ai.CompanionKind
---@param extra table? more CodeCompanion.chat() arguments
---@return CodeCompanion.Chat|nil
function M.new(kind, extra)
  if not M.preflight(kind) then return nil end
  local params = { adapter = M.adapter_name(kind) }
  if kind == "http" then params.model = config.codecompanion.model end
  local chat = require("codecompanion").chat(vim.tbl_extend("force", { params = params }, extra or {}))
  focus(chat)
  return chat
end

---Show or hide the chat of `kind`, starting one when there is none.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.toggle(kind)
  local chat = M.find(kind)
  if not chat then return M.new(kind) end
  if here(chat) then
    chat.ui:hide()
    return chat
  end
  show(chat, true)
  return chat
end

---Add the Visual selection to the chat of `kind` (CodeCompanion.add, aimed at
---one kind instead of `last_chat`), starting one when there is none. Nothing
---is submitted.
---@param kind ai.CompanionKind
---@return CodeCompanion.Chat|nil
function M.add_selection(kind)
  local buf = vim.api.nvim_get_current_buf()
  -- Leave Visual first: '< and '> then mark this selection, and the context is
  -- read exactly as :'<,'>CodeCompanionChat Add reads it, blockwise included.
  if vim.fn.mode():match("^[vV\22]") then vim.cmd("normal! \27") end
  local chat = M.find(kind)
  -- A refusal needs nothing loaded; with no chat yet, this one would start it.
  if not chat and not M.preflight(kind) then return nil end
  if not require("codecompanion.config").can_send_code() then
    vim.notify("Sending code to CodeCompanion is disabled", WARN, { title = "AI" })
    return nil
  end
  local context = require("codecompanion.utils.context").get(buf, { range = 2 })
  chat = chat or M.new(kind, { stop_context_insertion = true })
  if not chat then return nil end
  chat.prompt:add({
    content = ("Here is some code from %s:\n%s\n"):format(context.path,
      require("codecompanion.utils.markdown").form_codeblock(table.concat(context.lines, "\n"),
        { ft = context.filetype })),
  })
  if here(chat) then focus(chat) else show(chat) end
  return chat
end

---Keys for <leader>ae: the inline prompt's command line, or nothing when the
---key is missing. An expr mapping, so the refusal comes before the command
---line opens rather than after a prompt has been typed.
---@return string
function M.inline_keys()
  return M.preflight("http") and ":CodeCompanion " or "<Ignore>"
end

---Point CodeCompanion's defaults for new chats and requests at the current
---state. A no-op until the plugin has loaded: its `opts` read the same state
---at load time (lua/plugin/lsp/codecompanion.lua). The live config is written
---directly, never `vim.g.codecompanion_adapter`, which v20's cmd.lua resolves
---through `config.adapters[name]` -- nil -- and so falls back to the ACP chat
---adapter.
function M.sync()
  if not loaded() then return end
  local cc = require("codecompanion.config")
  cc.interactions.chat.adapter = config.codecompanion.acp_adapter
  cc.interactions.inline.adapter = config.http_adapter_spec()
  cc.interactions.cmd.adapter = config.http_adapter_spec()
end

return M
