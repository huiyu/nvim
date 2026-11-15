-- A minimal third-party host, deliberately without this repository on rtp.
local api = vim.api
local root, tmp = assert(vim.env.AGENT_PLUGIN_DIR), assert(vim.env.AGENT_TEST_TMP)
vim.opt.rtp = { vim.env.VIMRUNTIME, root }
vim.opt.packpath = {}
table.insert(package.loaders, 1, function(name)
  assert(not name:match("^config[.%w]*$") and not name:match("^util%.")
    and not name:match("^editor_core") and not name:match("^git_review"), "private dependency: " .. name)
end)
local checks = 0
local function check(value, why) checks = checks + 1; assert(value, why) end
local before = #api.nvim_list_wins()
local agent = require("agent_workbench")
check(#api.nvim_list_wins() == before and package.loaded["agent_workbench.state"] == nil, "require must be inert")
check(package.loaded.snacks == nil, "Snacks is absent")
local selected = assert(vim.env.AGENT_TEST_PROVIDER)
local custom_calls, requests = {}, {}
local failures, partial = {}, nil
local provider = selected
if selected == "snacks" then
  vim.opt.rtp:append(assert(vim.env.AGENT_SNACKS_DIR))
  require("snacks").setup({})
elseif selected == "custom" then
  provider = {}
  local native = require("agent_workbench.provider.native")
  for _, method in ipairs({ "open", "show", "hide", "send", "alive", "stop" }) do
    provider[method] = function(...)
      custom_calls[method] = (custom_calls[method] or 0) + 1
      if method == "open" then requests[#requests + 1] = ... end
      if failures[method] then
        if method == "open" then
          partial = native.open(...)
          error("fixture: partial open failed")
        end
        return false, { code = "unavailable", message = "fixture: " .. method .. " refused" }
      end
      return native[method](...)
    end
  end
end
local input = {
  panel = { width = 42 }, terminal = { provider = provider },
  native = { codex = { command = assert(vim.env.AGENT_TEST_PYTHON),
    args = { root .. "/tests/fake_agent.py", "argument with spaces", "日本語" }, wrap_tmux = false } },
}
local copy = vim.deepcopy(input)
vim.env.AGENT_TEST_MARKER = "child-only-marker"
agent.setup(input)
check(vim.deep_equal(input, copy), "setup must not mutate declaration")
check(#api.nvim_list_wins() == before and #agent.sessions() == 0, "setup starts nothing")
check(package.loaded["codecompanion"] == nil and package.loaded["git_review"] == nil, "optional integrations remain unloaded")
check(vim.fn.maparg("<leader>an", "n") == "", "library defaults install no host mappings")
check(not pcall(agent.setup, input), "setup has one lifecycle")
local opts = agent.options()
opts.panel.width = 1
check(agent.options().panel.width == 42, "effective options are isolated")
local resolved = require("agent_workbench.state")
check(#resolved.providers == 1 and resolved.providers[1].name == "codex", "default native provider is Codex only")
check(not pcall(resolved.build, { { name = "claude", label = "Claude", tui = { kind = "claude" } } }),
  "unimplemented Claude cannot be enabled by a declaration")
vim.cmd.cd(vim.fn.fnameescape(tmp))
local file = tmp .. "/file 日本語.txt"
vim.fn.writefile({ "source" }, file)
vim.cmd.edit(vim.fn.fnameescape(file))
for _, capture in ipairs({
  {}, { text = 123 }, { text = false, path = file }, { text = "draft", path = false },
  { path = "relative.txt" }, { path = "" }, { path = file, modified = "yes" },
}) do
  local ok, reason = agent.send_context("codex", capture)
  check(not ok and reason.code == "unsupported", "malformed context is refused")
  check(#agent.sessions() == 0 and #api.nvim_list_wins() == before,
    "invalid context starts no session and opens no view")
end
if selected == "custom" then
  failures.open = true
  local failed, reason = agent.open("codex")
  failures.open = nil
  check(not failed and reason.code == "unavailable" and agent.session("codex") == nil,
    "failed custom open leaves no registry entry")
  check(not api.nvim_buf_is_valid(partial.buf) and vim.fn.jobwait({ partial.channel }, 0)[1] ~= -1,
    "a partial open releases its reported PTY and buffer")
end
local session, err = agent.open("codex")
assert(session, vim.inspect(err))
local function text() return table.concat(api.nvim_buf_get_lines(session.buf, 0, -1, false), "") end
check(vim.wait(3000, function() return text():find("READY:", 1, true) end, 10), "actual PTY reaches ready")
check(text():find("argument with spaces", 1, true) and text():find("日本語", 1, true), "argv preserves spaces/CJK")
check(text():find("child-only-marker", 1, true), "environment reaches child")
check(vim.uv.fs_realpath(session.root) == vim.uv.fs_realpath(tmp), "session cwd/root matches editor")
local record = agent.session_of_buffer(session.buf)
check(record.kind == "codex" and record.id == "native:codex", "registry owns identity")
record.kind = "corrupted"
check(agent.session_of_buffer(session.buf).kind == "codex", "public record is a copy")
local again = agent.open("codex")
check(again.buf == session.buf and again.generation == session.generation, "repeated open reuses one session")
local transport = require("agent_workbench.terminal_provider")
-- Observe exact byte delivery through the provider contract, without Enter.
local registry_session
if selected == "custom" then registry_session = requests[1] end
local channel = vim.bo[session.buf].channel
check(agent.send_context("codex", { text = "draft 日本語" }), "context uses the public send operation")
vim.wait(60, function() return false end)
check(not text():find("SEEN:", 1, true), "draft remains unsubmitted")
vim.api.nvim_chan_send(channel, "\n")
check(vim.wait(2000, function() return text():find("SEEN:draft 日本語", 1, true) end, 10), "exact text reaches PTY")
-- A nested repository has a different project root from this running session.
-- Both contain same.txt, so a basename-only mention would identify the wrong file.
local other = tmp .. "/other project"
vim.fn.mkdir(other .. "/.git", "p")
vim.fn.writefile({ "session's file" }, tmp .. "/same.txt")
vim.fn.writefile({ "other project's file" }, other .. "/same.txt")
check(agent.send_context("codex", { path = assert(vim.uv.fs_realpath(other .. "/same.txt")) }),
  "another project's file can be added to the existing session")
vim.wait(60, function() return false end)
api.nvim_chan_send(channel, "\n")
check(vim.wait(2000, function() return text():find("SEEN:@other project/same.txt ", 1, true) end, 10),
  "file references resolve from the session root, not the file's project root")
if selected == "custom" then
  local notify, notes = vim.notify, {}
  vim.notify = function(message) notes[#notes + 1] = tostring(message) end
  failures.hide = true
  local slot = require("agent_workbench.slot")
  local count, reason = slot.cover()
  check(count == 0 and reason.code == "unavailable" and agent.session("codex").win ~= nil,
    "a refused hide is not counted and keeps its view/session")
  check(notes[1] and notes[1]:find("hide refused", 1, true), "hide refusal explains its cause")
  local opened = false
  local switched = slot.around({ id = "cc:unopened", kind = "chat", chat = {} }, function() opened = true end)
  check(not switched and not opened, "a rejected hide prevents opening a competing view")
  local last = vim.t.ai_slot_last
  local revealed, refusal = slot.reveal({ id = "cc:unopened", kind = "chat", chat = {} })
  check(not revealed and refusal.code == "unavailable" and vim.t.ai_slot_last == last,
    "a refused chat reveal propagates failure and preserves the last shown chat")
  failures.hide, vim.notify = nil, notify
end
check(agent.hide("codex") and agent.session("codex").alive, "hide preserves the process")
agent.show("codex")
check(agent.session("codex").buf == session.buf, "show preserves buffer")
local owner_tab = api.nvim_get_current_tabpage()
vim.cmd.tabnew()
local other_tab = api.nvim_get_current_tabpage()
api.nvim_win_set_buf(0, session.buf)
local copy_win = api.nvim_get_current_win()
agent.open("codex")
check(api.nvim_get_current_tabpage() == other_tab and api.nvim_get_current_win() == copy_win,
  "opening a visible copy focuses it without jumping to its owner")
agent.send_context("codex", { text = "copy draft" })
vim.wait(60, function() return false end)
check(api.nvim_get_current_tabpage() == other_tab and api.nvim_get_current_win() == copy_win,
  "delivery to a visible copy stays in its current tab")
local hidden, reason = agent.hide("codex")
check(not hidden and reason.code == "other_tab", "another tab cannot hide owned view")
api.nvim_set_current_tabpage(owner_tab)
local owned = agent.session("codex").win
for _, win in ipairs(api.nvim_tabpage_list_wins(owner_tab)) do
  if win ~= owned and api.nvim_win_get_config(win).relative == "" then api.nvim_win_close(win, true) end
end
local float = api.nvim_open_win(api.nvim_create_buf(false, true), false,
  { relative = "editor", width = 5, height = 2, row = 1, col = 1 })
hidden, reason = agent.hide("codex")
check(not hidden and reason.code == "only_window", "float does not make the last normal window closeable")
api.nvim_win_close(float, true)
if selected == "custom" then
  local notify = vim.notify
  vim.notify = function() end
  failures.hide = true
  local chat = { id = "rollback", ui = {} }
  local opened
  chat.ui.hide = function()
    api.nvim_win_close(opened, true)
  end
  local switched = require("agent_workbench.slot").around({ id = "cc:rollback", kind = "chat", chat = chat }, function()
    chat.bufnr = api.nvim_create_buf(false, true)
    opened = api.nvim_open_win(chat.bufnr, true, { split = "left" })
  end)
  check(not switched and not api.nvim_win_is_valid(opened) and api.nvim_win_is_valid(owned),
    "if the sole old view refuses to hide, the newly opened view is hidden again")
  api.nvim_buf_delete(chat.bufnr, { force = true })
  failures.hide, vim.notify = nil, notify
end
api.nvim_open_win(api.nvim_create_buf(false, true), true, { split = "left" })
if selected == "custom" then
  local notify, notes = vim.notify, {}
  vim.notify = function(msg) notes[#notes + 1] = msg end
  failures.send = true
  agent.send_context("codex", { text = "refused draft" })
  check(vim.wait(1000, function() return #notes > 0 end, 10) and notes[1]:find("send refused", 1, true),
    "deferred provider send refusal is visible to the caller")
  failures.send, vim.notify = nil, notify
  failures.stop = true
  local stopped, reason = agent.stop("codex")
  failures.stop = nil
  check(not stopped and reason.code == "unavailable" and agent.session("codex").alive,
    "provider stop refusal preserves the live registry for retry")
end
agent.stop("codex")
check(agent.session("codex") == nil and vim.fn.jobwait({ channel }, 0)[1] ~= -1, "stop releases process/registry")
check(agent.stop("codex"), "stop is idempotent")
if selected == "custom" then
  vim.cmd.edit(vim.fn.fnameescape(file))
  agent.open("codex")
  check(#requests == 3, "custom provider owns the partial and both successful launches")
  registry_session.on_exit(0)
  check(agent.session("codex").generation ~= session.generation, "stale exit cannot remove newer generation")
  agent.stop("codex")
  check(custom_calls.open == 3 and custom_calls.hide and custom_calls.show and custom_calls.stop,
    "same public lifecycle uses custom implementation")
  check(custom_calls.send ~= nil, "public context delivery uses custom provider.send")
end
check(package.loaded["codecompanion"] == nil and package.loaded["git_review"] == nil, "native use needs no chat/review package")
if selected ~= "snacks" then check(package.loaded.snacks == nil, "native/custom use never imports Snacks") end
if api.nvim_tabpage_is_valid(other_tab) then api.nvim_set_current_tabpage(other_tab) end
vim.fn.writefile({ vim.json.encode({ checks = checks, provider = selected }) }, assert(vim.env.AGENT_TEST_OUTPUT))
vim.cmd("cquit 0")
