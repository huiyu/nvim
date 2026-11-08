-- Guards the native agents' review hooks (lua/ai/review/hook.lua and
-- scripts/agent-hook): what each CLI is given, that it reaches the CLI byte for
-- byte through both launch paths of both wrappers, and that the script never
-- prints, always exits 0 and keeps every wait bounded. The script runs end to
-- end against a real headless Nvim over --listen, with ai.review.rounds stubbed
-- there, so nothing takes a baseline. No real agent is started and no prompt is
-- sent; the optional checks at the end only ask the installed CLIs to validate
-- the injected configuration offline, in isolated config homes.
local t = dofile("tests/helper.lua")

local hook = require("ai.review.hook")
local ai_config = require("ai.config")
local codex = require("ai.backend.codex")

local script = hook.script()
local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, "p")

---Run fn with vim.g.ai_review set to `value`, restoring it whatever happens.
local function with_review(value, fn)
  local saved = vim.g.ai_review
  vim.g.ai_review = value
  local ok, err = pcall(fn)
  vim.g.ai_review = saved
  if not ok then error(err, 0) end
end

---Run fn with environment variables set (false unsets), restoring them after.
local function with_env(vars, fn)
  local saved = {}
  for k, v in pairs(vars) do
    saved[k] = vim.env[k] or false
    vim.env[k] = v or nil
  end
  local ok, res = pcall(fn)
  for k, v in pairs(saved) do vim.env[k] = v or nil end
  if not ok then error(res, 0) end
  return res
end

---The process environment minus `drop`, plus `add`, for clear_env launches.
local function environ(drop, add)
  local env = vim.fn.environ()
  for _, k in ipairs(drop) do env[k] = nil end
  for k, v in pairs(add or {}) do env[k] = v end
  return env
end

---claudecode's terminal_cmd exactly as lazy evaluates it, under `vars`.
local function claude_terminal_cmd(vars)
  return with_env(vars, function() return dofile("lua/plugin/lsp/ai.lua")[1].opts.terminal_cmd end)
end

---------------------------------------------------------------------------
-- What Claude is given: --settings JSON, exec form
---------------------------------------------------------------------------

t.ok(script:sub(1, 1) == "/" and vim.fn.executable(script) == 1, "scripts/agent-hook is present, absolute and executable")

local settings = vim.json.decode(hook.claude_settings())
local events = vim.tbl_keys(settings.hooks or {})
table.sort(events)
t.eq(events, { "SessionStart", "UserPromptSubmit" }, "Claude gets UserPromptSubmit and SessionStart, nothing else")
t.eq(settings.hooks.UserPromptSubmit, {
  { hooks = { { type = "command", command = script, args = { "claude", "submit", "2500" }, timeout = 10 } } },
}, "UserPromptSubmit runs the script in exec form, with the wait in argv and a 10 s hard cap")
t.eq(settings.hooks.SessionStart, {
  { hooks = { { type = "command", command = script, args = { "claude", "session", "2500" }, async = true } } },
}, "SessionStart runs it async, so a session report never holds the TUI")
with_review({ hook_wait_ms = 20000 }, function()
  local ups = vim.json.decode(hook.claude_settings()).hooks.UserPromptSubmit[1].hooks[1]
  t.eq({ ups.args[3], ups.timeout }, { "20000", 25 }, "hook_wait_ms travels in argv and the hard cap grows with it")
end)

---------------------------------------------------------------------------
-- What Codex is given: -c hooks=..., with the trust hash
---------------------------------------------------------------------------

-- Fixed vectors from the Python reference (json.dumps sort_keys, compact,
-- ensure_ascii=False), which matched the trusted_hash values Codex itself wrote
-- for five existing hooks. The second one pins the string escaping.
t.eq(hook.codex_trust_hash("user_prompt_submit", "'/cfg dir/scripts/agent-hook' codex submit 2500", 10),
  "sha256:6407f82ca445a970baea9f6c0305a6b249e7650c36473b2fbcf3cd6abb514e89",
  "the trust hash matches the reference for a plain command")
t.eq(hook.codex_trust_hash("user_prompt_submit", "'/a/it'\\''s \"q\" \\ \u{e9}\t/agent-hook' codex submit 0", 15),
  "sha256:1db5dbb7983e912572628bbfdf4000bc8a40ec17d66ec4fd32826e3c071cc473",
  "and for one with quotes, a backslash, a tab and non-ASCII")
t.eq(hook.codex_trust_hash("user_prompt_submit", '"$HOME/.local/bin/agentdeck" ingest claude', 600),
  "sha256:e94f32aca17ec3e6a7e7aec6fd161d8dc6cceb2bfffb57e1548d2fd11fb3c3fd",
  "and for a user hook of the kind Codex hashed itself")

local override = hook.codex_override()
local command = vim.fn.shellescape(script) .. " codex submit 2500"
local toml_command = command:gsub("\\", "\\\\"):gsub('"', '\\"')
t.ok(vim.startswith(override, "hooks={UserPromptSubmit=[{hooks=[{type=\"command\",command=\"" .. toml_command
  .. "\",timeout=10}]}],state={"), "the override is one inline table holding the UserPromptSubmit hook")
t.ok(override:find(('"%s"={trusted_hash="%s"}'):format(hook.CODEX_TRUST_KEY,
  hook.codex_trust_hash("user_prompt_submit", command, 10)), 1, true) ~= nil,
  "and its trust state, keyed by the session-flags layer, hashed from the same command")
t.ok(not override:find("SessionStart", 1, true) and not override:find("notify", 1, true),
  "Codex gets no SessionStart (it waits for the first turn) and its notify is left alone")

t.eq(vim.list_slice(codex._codex_command({ "resume", "--last" }), 1, 5),
  { "codex", "--no-alt-screen", "--yolo", "-c", override }, "codex_command puts the override in front of its arguments")
t.eq(codex._codex_command({ "resume", "--last" })[6], "resume", "and keeps the arguments after it")

---------------------------------------------------------------------------
-- The source toggles
---------------------------------------------------------------------------

with_review({ sources = { claude = false } }, function()
  for _, wrap in ipairs({ "0", "1" }) do
    local cmd = claude_terminal_cmd({ CLAUDE_WRAP_TMUX = wrap })
    t.ok(not cmd:find("--settings", 1, true), "sources.claude = false: no --settings (CLAUDE_WRAP_TMUX=" .. wrap .. ")")
  end
  t.eq(codex._codex_command({})[4], "-c", "sources.claude = false leaves Codex's hook in place")
end)
with_review({ sources = { codex = false } }, function()
  t.eq(codex._codex_command({ "resume" }), { "codex", "--no-alt-screen", "--yolo", "resume" },
    "sources.codex = false: Codex starts exactly as before")
  t.ok(claude_terminal_cmd({ CLAUDE_WRAP_TMUX = "0" }):find("--settings", 1, true) ~= nil,
    "sources.codex = false leaves Claude's hook in place")
end)

---------------------------------------------------------------------------
-- The argv each agent receives, byte for byte, through every launch path
---------------------------------------------------------------------------

-- Stand-ins named after each CLI record their argv (NUL-separated) and the
-- three variables the ctrl+g editor handoff depends on.
local bin = scratch .. "/bin"
vim.fn.mkdir(bin, "p")
local function stand_in(name)
  local out = scratch .. "/" .. name
  vim.fn.writefile({
    "#!/bin/sh",
    "out=" .. vim.fn.shellescape(out),
    ': > "$out.tmp"',
    [[for a in "$@"; do printf '%s\0' "$a" >> "$out.tmp"; done]],
    [[printf 'EDITOR=%s\0VISUAL=%s\0NVIM=%s\0' "${EDITOR-}" "${VISUAL-}" "${NVIM-}" > "$out.env"]],
    'mv "$out.tmp" "$out.argv"',
  }, bin .. "/" .. name)
  vim.fn.setfperm(bin .. "/" .. name, "rwx------")
  return out
end
local recorded = { claude = stand_in("claude"), codex = stand_in("codex") }

local function read_nul(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local parts = vim.split(data, "\0", { plain = true })
  if parts[#parts] == "" then parts[#parts] = nil end
  return parts
end

local function remove_socket(socket)
  local dir = (vim.env.TMUX_TMPDIR and vim.env.TMUX_TMPDIR ~= "") and vim.env.TMUX_TMPDIR or "/tmp"
  for _, path in ipairs(vim.fn.glob(dir .. "/tmux-*/" .. socket, false, true)) do vim.fn.delete(path) end
end

local search_path = bin .. ":" .. vim.env.PATH

---Start `cmd` as the agent terminal would and return what the stand-in saw.
---Nothing starts unless `agent` resolves to the stand-in: jobstart looks a list
---command up on Nvim's own PATH, and the real CLI must never run here.
---@param agent "claude"|"codex"
---@param cmd string|string[]
---@param socket string? the wrapper's tmux server, removed afterwards
local function launch(agent, cmd, socket)
  local out = recorded[agent]
  vim.fn.delete(out .. ".argv")
  vim.fn.delete(out .. ".env")
  local resolved = with_env({ PATH = search_path }, function() return vim.fn.exepath(agent) end)
  if resolved ~= bin .. "/" .. agent then
    t.ok(false, agent .. " resolves to the stand-in, so the real CLI never starts (got " .. resolved .. ")")
    return nil, {}
  end
  with_env({ PATH = search_path }, function()
    local opts = { cwd = scratch, env = { PATH = search_path, NVIM = vim.v.servername } }
    -- A tmux client needs a terminal.
    if socket then opts.pty, opts.width, opts.height = true, 100, 30 end
    local job = vim.fn.jobstart(cmd, opts)
    vim.wait(10000, function() return vim.uv.fs_stat(out .. ".argv") ~= nil end, 20)
    vim.fn.jobwait({ job }, 5000)
    pcall(vim.fn.jobstop, job)
  end)
  if socket then
    vim.system({ "tmux", "-L", socket, "kill-server" }):wait()
    remove_socket(socket)
  end
  local env = {}
  for _, kv in ipairs(read_nul(out .. ".env") or {}) do
    local k, v = kv:match("^([^=]+)=(.*)$")
    if k then env[k] = v end
  end
  return read_nul(out .. ".argv"), env
end

local wrapper = require("ai.editor").wrapper()
local tmux = vim.fn.executable("tmux") == 1

-- Claude: claudecode appends its own arguments (--resume <id>) to terminal_cmd
-- and runs the string through the shell.
local plugin_dir = scratch .. "/plug in"
local claude_want = { "--plugin-dir", plugin_dir, "--settings", hook.claude_settings(), "--resume", "abc-123" }
for _, wrap in ipairs(tmux and { "0", "1" } or { "0" }) do
  local cmd = claude_terminal_cmd({ CLAUDE_WRAP_TMUX = wrap, CLAUDE_CHROME = "0", CLAUDE_PLUGIN_DIR = plugin_dir })
  local path = wrap == "1" and "tmux" or "direct"
  t.eq(ai_config.provider_of_command(cmd), "claude", "Claude (" .. path .. "): provider_of_command still finds the agent")
  local argv, env = launch("claude", cmd .. " --resume abc-123", wrap == "1" and "claude-nvim-" .. vim.fn.getpid() or nil)
  t.eq(argv, claude_want, "Claude (" .. path .. "): --settings arrives byte for byte, appended arguments after it")
  t.eq(env, { EDITOR = wrapper, VISUAL = wrapper, NVIM = vim.v.servername },
    "Claude (" .. path .. "): EDITOR, VISUAL and NVIM still reach the agent")
end

-- Codex: the list goes to jobstart without a shell, and under tmux as a
-- multi-argument pane command.
local codex_want = { "--no-alt-screen", "--yolo", "-c", override, "resume", "--last" }
for _, wrap in ipairs(tmux and { "0", "1" } or { "0" }) do
  local cmd = with_env({ CODEX_WRAP_TMUX = wrap }, function()
    return codex._terminal_command(codex._codex_command({ "resume", "--last" }))
  end)
  local path = wrap == "1" and "tmux" or "direct"
  t.eq(ai_config.provider_of_command(cmd), "codex", "Codex (" .. path .. "): provider_of_command still finds the agent")
  local argv, env = launch("codex", cmd, wrap == "1" and "codex-nvim-" .. vim.fn.getpid() or nil)
  t.eq(argv, codex_want, "Codex (" .. path .. "): the TOML override arrives byte for byte, resume after it")
  if wrap == "1" then
    t.eq(env, { EDITOR = wrapper, VISUAL = wrapper, NVIM = vim.v.servername },
      "Codex (tmux): EDITOR, VISUAL and NVIM still reach the agent")
  end
end

---------------------------------------------------------------------------
-- The receiver on its own
---------------------------------------------------------------------------

do
  local notes = {}
  local real_notify = vim.notify
  vim.notify = function(msg) notes[#notes + 1] = msg end
  local missing = scratch .. "/no-such-payload"
  t.eq(hook.event("gemini", "submit", missing, missing .. ".done"), "error:usage", "an unknown agent is refused")
  t.eq(hook.event("codex", "session", missing, missing .. ".done"), "error:usage", "so is an event that was never injected")
  t.eq(hook.event("claude", "submit", missing, missing .. ".done"), "missed",
    "a payload the script already removed is a missed submit")
  vim.wait(200, function() return #notes > 0 end, 10)
  vim.notify = real_notify
  t.ok(#notes == 1 and notes[1]:find("Missed a Claude Code prompt submit", 1, true) ~= nil,
    "and says so, once: that prompt has no baseline")
  t.ok(vim.uv.fs_stat(missing .. ".done") == nil, "and leaves no release file behind")
end

---------------------------------------------------------------------------
-- The script, end to end against a real headless Nvim
---------------------------------------------------------------------------

local sock = scratch .. "/host.sock"
local child = vim.fn.jobstart({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "--listen", sock },
  { cwd = vim.fn.getcwd(), stdin = "null" })
local chan
vim.wait(15000, function()
  local ok, c = pcall(vim.fn.sockconnect, "pipe", sock, { rpc = true })
  if ok and c > 0 then chan = c end
  return chan ~= nil
end, 50)
t.ok(chan ~= nil, "a headless Nvim is listening for the hook")

local function remote(code, ...)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
end

-- The stub stands in for ai.review.rounds, so no baseline is ever taken: it
-- records each event and, depending on `mode`, releases the hook after 150 ms
-- or never.
if chan then
  remote([[
    _G.hook_spec = { calls = {}, notes = {}, mode = "release" }
    vim.notify = function(msg) table.insert(_G.hook_spec.notes, msg) end
    package.loaded["ai.review.rounds"] = {
      native_event = function(ev)
        table.insert(_G.hook_spec.calls, {
          agent = ev.agent, event = ev.event, payload = ev.payload, waiting = not ev.gave_up(),
        })
        _G.hook_spec.last = ev
        if _G.hook_spec.mode == "release" then vim.defer_fn(ev.done, 150) end
      end,
    }
  ]])
end

local hook_tmp = scratch .. "/hook-tmp"
vim.fn.mkdir(hook_tmp, "p")

---@return { code: integer, stdout: string, stderr: string, ms: number }
local function run_hook(args, payload, nvim)
  local env = environ({ "NVIM" }, { TMPDIR = hook_tmp, NVIM = nvim })
  local start = vim.uv.hrtime()
  local res = vim.system(vim.list_extend({ script }, args), {
    stdin = payload, env = env, clear_env = true, text = true,
  }):wait(10000)
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "", ms = (vim.uv.hrtime() - start) / 1e6 }
end

local function silent_ok(res) return res.code == 0 and res.stdout == "" and res.stderr == "" end
local function calls() return chan and #remote("return _G.hook_spec.calls") or 0 end
local function leftovers() return vim.fn.readdir(hook_tmp) end

---The fastest of three runs: a fail-fast path is about not burning the budget,
---and one slow fork on a loaded machine should not read as burning it.
local function fastest(args, payload, nvim)
  local best
  for _ = 1, 3 do
    local res = run_hook(args, payload, nvim)
    if not best or res.ms < best.ms then best = res end
  end
  return best
end

local submit = vim.json.encode({ session_id = "s-1", cwd = scratch, prompt = "hi", turn_id = "t-1" })

-- Best of three here too: the first exec of a freshly written script pays a
-- one-time scan on macOS (~0.4 s measured), which says nothing about the script.
local res = fastest({ "claude", "submit", "2500" }, submit, nil)
t.ok(silent_ok(res) and res.ms < 100, ("no NVIM: silent exit 0 at once (%.0f ms)"):format(res.ms))
t.eq(leftovers(), {}, "and no payload file was made")

res = fastest({ "codex", "submit", "2500" }, submit, scratch .. "/dead.sock")
t.ok(silent_ok(res) and res.ms < 100, ("a closed socket: silent exit 0 within 100 ms (%.0f ms)"):format(res.ms))
t.eq(leftovers(), {}, "and the payload is cleaned up")
for _, bad in ipairs({ "08", "-1", "soon", "" }) do
  res = run_hook({ "codex", "submit", bad }, submit, scratch .. "/dead.sock")
  t.ok(silent_ok(res), ("a malformed wait (%q) still exits 0 silently"):format(bad))
end

if chan then
  local before = calls()
  res = run_hook({ "gemini", "submit", "2500" }, submit, sock)
  t.ok(silent_ok(res) and calls() == before, "an unknown agent never reaches Nvim")

  remote([[
    _G.hook_spec.real_hook = package.loaded["ai.review.hook"]
    package.loaded["ai.review.hook"] = { event = function() error("spec: the receiver raised") end }
  ]])
  res = fastest({ "claude", "submit", "2500" }, submit, sock)
  remote([[package.loaded["ai.review.hook"] = _G.hook_spec.real_hook]])
  t.ok(silent_ok(res) and res.ms < 100, ("a raising receiver: silent exit 0 within 100 ms (%.0f ms)"):format(res.ms))
  t.eq(leftovers(), {}, "and the payload is cleaned up")

  -- A submit is held until the baseline lands, and no longer.
  before = calls()
  res = run_hook({ "claude", "submit", "2500" }, submit, sock)
  local got = remote("return _G.hook_spec.calls")[before + 1]
  t.ok(silent_ok(res) and res.ms >= 150 and res.ms < 2000,
    ("a submit is held until the receiver releases it (%.0f ms), silently"):format(res.ms))
  t.eq(got and { got.agent, got.event, got.payload.session_id, got.payload.turn_id, got.waiting },
    { "claude", "submit", "s-1", "t-1", true }, "rounds.native_event got the decoded payload while the hook waited")
  t.eq(leftovers(), {}, "and the payload is cleaned up")

  -- Never released: the wait ends at the budget, and Nvim can tell it was late.
  remote([[_G.hook_spec.mode = "hold"]])
  res = run_hook({ "codex", "submit", "300" }, submit, sock)
  t.ok(silent_ok(res) and res.ms >= 300 and res.ms < 1500,
    ("an unreleased submit gives up at the configured wait (%.0f ms for 300)"):format(res.ms))
  t.ok(remote("return _G.hook_spec.last.agent == 'codex' and _G.hook_spec.last.gave_up()"),
    "and the late receiver finds the payload gone")
  remote("_G.hook_spec.last.done()")
  t.eq(leftovers(), {}, "a release after the script gave up leaves nothing in TMPDIR")

  res = run_hook({ "claude", "submit", "0" }, submit, sock)
  t.ok(silent_ok(res) and res.ms < 500, ("a zero wait only delivers (%.0f ms)"):format(res.ms))

  -- A session event is released by the receiver itself.
  before = calls()
  res = run_hook({ "claude", "session", "2500" }, vim.json.encode({ session_id = "s-2", source = "resume" }), sock)
  got = remote("return _G.hook_spec.calls")[before + 1]
  t.ok(silent_ok(res) and res.ms < 500, ("a session event returns once delivered (%.0f ms)"):format(res.ms))
  t.eq(got and { got.event, got.payload.source }, { "session", "resume" }, "and is forwarded as a session event")

  -- Subagents and spawned threads belong to the parent's turn.
  before = calls()
  res = run_hook({ "codex", "submit", "2500" },
    vim.json.encode({ session_id = "s-1", turn_id = "t-9", agent_id = "sub-1", agent_type = "worker" }), sock)
  t.ok(silent_ok(res) and res.ms < 500 and calls() == before,
    ("an event carrying agent_id is dropped and released at once (%.0f ms)"):format(res.ms))
  before = calls()
  res = run_hook({ "claude", "session", "2500" }, vim.json.encode({ session_id = "s-3", agent_id = "a" }), sock)
  t.ok(silent_ok(res) and calls() == before, "for session events too")

  -- The source toggles, read per event.
  remote([[vim.g.ai_review = { sources = { claude = false } }]])
  before = calls()
  res = run_hook({ "claude", "submit", "2500" }, submit, sock)
  t.ok(silent_ok(res) and res.ms < 500 and calls() == before,
    ("sources.claude = false: a Claude submit is released and dropped (%.0f ms)"):format(res.ms))
  remote([[_G.hook_spec.mode = "release"]])
  res = run_hook({ "codex", "submit", "2500" }, submit, sock)
  got = remote("return _G.hook_spec.calls")[before + 1]
  t.ok(silent_ok(res) and got ~= nil and got.agent == "codex", "while Codex's still reaches the receiver")
  remote([[vim.g.ai_review = { sources = { codex = false } }]])
  before = calls()
  res = run_hook({ "codex", "submit", "2500" }, submit, sock)
  t.ok(silent_ok(res) and calls() == before, "sources.codex = false: a Codex submit is dropped")
  remote([[vim.g.ai_review = nil]])

  -- A busy Nvim: the prompt goes ahead at the budget, and the late request
  -- never takes a baseline after the agent may already have written. Nvim may
  -- also drop that request outright, its client having been killed; when it
  -- does serve it, the receiver finds the payload gone and reports the miss.
  before = calls()
  local notes_before = #remote("return _G.hook_spec.notes")
  vim.rpcnotify(chan, "nvim_exec_lua", "vim.uv.sleep(1500)", {})
  vim.wait(50)
  res = run_hook({ "claude", "submit", "300" }, submit, sock)
  t.ok(silent_ok(res) and res.ms < 1200,
    ("a blocked Nvim does not hold the prompt past the budget (%.0f ms)"):format(res.ms))
  remote("return 1") -- returns once the child is serving requests again
  vim.wait(300)
  local late = vim.list_slice(remote("return _G.hook_spec.notes"), notes_before + 1)
  t.ok(calls() == before and (#late == 0 or late[1]:find("Missed a Claude Code prompt submit", 1, true) ~= nil),
    "the late request takes no baseline (and, if served, reports the missed submit)")
  t.eq(leftovers(), {}, "and nothing is left in TMPDIR")

  -- Without ai.review.rounds the receiver acknowledges and drops the event.
  if #remote([[return vim.loader.find("ai.review.rounds")]]) == 0 then
    remote([[package.loaded["ai.review.rounds"] = nil]])
    res = run_hook({ "claude", "submit", "2500" }, submit, sock)
    t.ok(silent_ok(res) and res.ms < 500, ("without ai.review.rounds a submit is released at once (%.0f ms)"):format(res.ms))
  end

  pcall(vim.rpcnotify, chan, "nvim_command", "qa!")
  vim.fn.jobwait({ child }, 5000)
  pcall(vim.fn.chanclose, chan)
end
pcall(vim.fn.jobstop, child)

---------------------------------------------------------------------------
-- Optional: the installed CLIs accept what is injected (no prompt, no auth)
---------------------------------------------------------------------------

local BILLING = { "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY" }

-- `claude doctor` reports a settings file it cannot accept under "Invalid
-- settings" (and still exits 0). The broken control shows the check can fail.
if vim.fn.executable("claude") == 1 then
  local home = scratch .. "/claude-config"
  vim.fn.mkdir(home, "p")
  local function doctor(json)
    local r = vim.system({ "claude", "--settings", json, "doctor" }, {
      cwd = scratch, env = environ(BILLING, { CLAUDE_CONFIG_DIR = home }), clear_env = true, text = true,
    }):wait(60000)
    return r.code, (r.stdout or "") .. (r.stderr or "")
  end
  local code, out = doctor(hook.claude_settings())
  t.ok(code == 0 and out:find("Claude Code doctor", 1, true) ~= nil and not out:find("Invalid settings", 1, true),
    "claude doctor accepts the injected --settings")
  local _, bad = doctor('{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"commandx","command":"x"}]}]}}')
  t.ok(bad:find("Invalid settings", 1, true) ~= nil, "and rejects a broken one, so the check can fail")
end

-- `codex app-server` lists hooks with their trust status over JSON-RPC. In an
-- isolated CODEX_HOME there is no login, so nothing can reach a model.
if vim.fn.executable("codex") == 1 then
  local function hooks_list(value)
    local home = vim.fn.tempname()
    vim.fn.mkdir(home, "p")
    local buf = ""
    local proc = vim.system({ "codex", "app-server", "-c", value }, {
      cwd = scratch, env = environ(BILLING, { CODEX_HOME = home }), clear_env = true, stdin = true,
      stdout = function(_, data) if data then buf = buf .. data end end,
    })
    for _, msg in ipairs({
      { jsonrpc = "2.0", id = 1, method = "initialize", params = { clientInfo = { name = "nvim-spec", version = "0" } } },
      { jsonrpc = "2.0", method = "initialized" },
      { jsonrpc = "2.0", id = 2, method = "hooks/list", params = { cwds = { scratch } } },
    }) do
      proc:write(vim.json.encode(msg) .. "\n")
    end
    local reply
    vim.wait(20000, function()
      for line in buf:gmatch("[^\n]+") do
        local ok, msg = pcall(vim.json.decode, line)
        if ok and type(msg) == "table" and msg.id == 2 then reply = msg end
      end
      return reply ~= nil
    end, 50)
    proc:kill(15)
    proc:wait(2000)
    vim.fn.delete(home, "rf")
    for _, data in ipairs(reply and reply.result and reply.result.data or {}) do
      for _, h in ipairs(data.hooks or {}) do
        if h.key == hook.CODEX_TRUST_KEY then return h end
      end
    end
  end

  local listed = hooks_list(override)
  t.eq(listed and { listed.source, listed.trustStatus, listed.command, listed.timeoutSec },
    { "sessionFlags", "trusted", command, 10 }, "codex lists the injected hook as trusted, command intact")

  -- A path that needs both shell and TOML escaping, and a zero wait.
  local real_script = hook.script
  hook.script = function() return "/tmp/it's \"a\" dir\\x/agent-hook" end
  local odd_ok, odd = pcall(with_review, { hook_wait_ms = 0 }, function() listed = hooks_list(hook.codex_override()) end)
  hook.script = real_script
  t.ok(odd_ok and listed ~= nil and listed.trustStatus == "trusted", "and stays trusted when the path needs escaping"
    .. (odd_ok and "" or (": " .. tostring(odd))))
end

vim.fn.delete(scratch, "rf")
t.done()
