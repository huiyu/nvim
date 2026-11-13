-- The progress line of a CodeCompanion chat: from the moment a prompt is
-- sent until the turn ends, the end of the chat's last line says so, with a
-- spinner and the seconds since the send.
--
-- Upstream shows nothing between a submit and the first streamed chunk, so a
-- slow first token reads as a key that did not register (upstream #3488).
-- The community's spinners (doc/extending/ui.md, codecompanion-spinners.nvim)
-- start on `User CodeCompanionRequestStarted`, which comes late: an ACP chat
-- fires it only once its connection and session are up, an HTTP chat after
-- the adapter's setup, which can block on fetching the model list. This
-- starts from the chat's `on_submitted` callback instead, which Chat:submit
-- dispatches before either, and redraws at once so the line is on screen
-- before anything blocks.
--
-- While a reply streams in, its text is the feedback and the line is hidden;
-- it comes back once the buffer has not changed for STALL_MS (an agent
-- thinking, or running a tool), and is gone once the chat is no longer busy
-- (ai.companion.busy: done, stopped, failed, cleared or closed).
--
-- Reads a chat's `add_callback`, `bufnr` and `adapter` (the name, through
-- ai.companion.name), as ai.review.rounds does for on_before_submit.

local M = {}

M.TICK_MS = 100
M.STALL_MS = 1500
M.ns = vim.api.nvim_create_namespace("ai_chat_progress")

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

vim.api.nvim_set_hl(0, "AiChatProgress", { link = "Comment", default = true })

---@class ai.ProgressState
---@field chat table
---@field timer uv.uv_timer_t
---@field started number ms, when the turn's first prompt was sent
---@field tick integer the buffer's changedtick last seen
---@field changed number ms, when that changedtick was first seen
---@field output boolean has the buffer changed since the last send?
---@field frame integer
---@field mark? integer

---@type table<integer, ai.ProgressState> by chat buffer
local active = {}
---@type table<table, true> chats whose on_submitted is hooked
local attached = setmetatable({}, { __mode = "k" })

local function now() return vim.uv.hrtime() / 1e6 end

local function stop(buf)
  local state = active[buf]
  if not state then return end
  active[buf] = nil
  state.timer:stop()
  if not state.timer:is_closing() then state.timer:close() end
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1) end
end

---Draw, move or hide the line for `buf`, or end it with the turn.
---@param buf integer
local function update(buf)
  local state = active[buf]
  if not state then return end
  local companion = require("ai.companion")
  if not vim.api.nvim_buf_is_valid(buf) or not companion.busy(state.chat) then return stop(buf) end
  local t = now()
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if tick ~= state.tick then state.tick, state.changed, state.output = tick, t, true end
  if state.output and t - state.changed < M.STALL_MS then
    if state.mark then
      vim.api.nvim_buf_del_extmark(buf, M.ns, state.mark)
      state.mark = nil
    end
    return
  end
  state.frame = state.frame % #FRAMES + 1
  local name = companion.name(state.chat)
  local what = state.output and (name .. " is working") or ("Waiting for " .. name)
  local text = ("  %s %s · %ds"):format(FRAMES[state.frame], what, math.floor((t - state.started) / 1000))
  -- The end of the buffer moves as the reply is written, so the mark is put
  -- back on the last line every time rather than left to follow it.
  state.mark = vim.api.nvim_buf_set_extmark(buf, M.ns, vim.api.nvim_buf_line_count(buf) - 1, 0, {
    id = state.mark,
    virt_text = { { text, "AiChatProgress" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

---A prompt of `chat` was sent: start its line, or, for the next step of a
---turn already running (a tool loop's auto-submit), wait for output again.
---@param chat table a CodeCompanion.Chat
function M.start(chat)
  local buf = type(chat) == "table" and chat.bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local state = active[buf]
  if state then
    state.output, state.tick = false, vim.api.nvim_buf_get_changedtick(buf)
  else
    state = {
      chat = chat,
      timer = assert(vim.uv.new_timer()),
      started = now(),
      tick = vim.api.nvim_buf_get_changedtick(buf),
      changed = now(),
      output = false,
      frame = 0,
    }
    active[buf] = state
    state.timer:start(M.TICK_MS, M.TICK_MS, vim.schedule_wrap(function()
      local ok = pcall(update, buf)
      if not ok then stop(buf) end
    end))
  end
  update(buf)
  -- Chat:submit goes on to work that can block the loop (an HTTP adapter's
  -- model list): put the line on screen first.
  pcall(vim.cmd.redraw)
end

---Is `buf`'s progress line running?
---@param buf integer
---@return boolean
function M.running(buf) return active[buf] ~= nil end

---Hook `chat`'s on_submitted, once.
---@param chat table a CodeCompanion.Chat
function M.attach(chat)
  if type(chat) ~= "table" or attached[chat] or type(chat.add_callback) ~= "function" then return end
  attached[chat] = true
  chat:add_callback("on_submitted", function(c) M.start(c or chat) end)
end

---`User CodeCompanionChatCreated`: hook the chat. Fires only from a loaded
---CodeCompanion, so nothing is loaded to answer.
---@param data? { bufnr?: integer }
function M.chat_created(data)
  if type(data) ~= "table" or not data.bufnr then return end
  local chat = require("ai.companion").chat_of(data.bufnr)
  if chat then M.attach(chat) end
end

return M
