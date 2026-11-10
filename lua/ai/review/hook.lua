-- The native agents' prompt hooks: what gets injected into each CLI, and the
-- RPC receiver scripts/agent-hook calls back into.
--
-- Both agents are given a hook per process, never through the user's own
-- settings: Claude through `--settings <json>` (lua/plugin/lsp/ai.lua), Codex
-- through `-c hooks=...` (lua/ai/backend/codex.lua). Both merge with whatever
-- hooks the user configured instead of replacing them. Each is gated by
-- sources.claude / sources.codex in ai.review.config.
--
--   agent  event                 hook script call
--   claude UserPromptSubmit      agent-hook claude submit <wait-ms>
--   claude SessionStart (async)  agent-hook claude session <wait-ms>
--   codex  UserPromptSubmit      agent-hook codex submit <wait-ms>
--
-- Codex gets no SessionStart: it only runs at the thread's first turn
-- (session.rs queue_pending_session_start_source), never earlier than the
-- first UserPromptSubmit, so it would tell us nothing new.
--
-- The script cannot read Lua settings, so hook_wait_ms travels in its argv.
-- Generating either string is pure string work: the plugin spec calls
-- claude_settings() at startup, so this module must not load a plugin or run
-- git. ai.review.rounds is only required when an event arrives.

local M = {}

-- Which events the script forwards, per agent. Mirrors the case in
-- scripts/agent-hook; anything else is refused on both sides.
local ROUTES = { claude = { submit = true, session = true }, codex = { submit = true } }

-- Codex keys a hook's trust state by layer, event, group and handler index. The
-- session-flags layer has a synthetic path, and the one injected group holds a
-- single handler (hooks/src/lib.rs hook_key, engine/discovery.rs).
M.CODEX_TRUST_KEY = "/<session-flags>/config.toml:user_prompt_submit:0:0"

---Absolute path of the hook script both agents run.
---@return string
function M.script()
  return vim.fn.stdpath("config") .. "/scripts/agent-hook"
end

---The hook's hard timeout in seconds: the configured wait plus room for the RPC
---round trip, and never under 10 s. Past it the CLI kills the hook and lets the
---prompt through anyway, so it only matters if the script itself misbehaves.
---@param wait_ms integer
---@return integer
local function hook_timeout(wait_ms)
  return math.max(10, math.ceil(wait_ms / 1000) + 5)
end

-- JSON, encoded by hand: Codex hashes a hook with its keys sorted and its
-- strings escaped the way serde_json does, and vim.json.encode guarantees
-- neither. The same encoder writes Claude's settings, so both outputs are
-- deterministic.
local JSON_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function json_string(s)
  -- serde_json escapes the quote, the backslash and C0 controls only: not "/",
  -- not DEL, not non-ASCII (written as raw UTF-8).
  return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
    return JSON_ESCAPES[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function json_encode(value)
  local kind = type(value)
  if kind == "string" then return json_string(value) end
  if kind == "boolean" then return tostring(value) end
  if kind == "number" then return ("%d"):format(value) end
  assert(kind == "table", "cannot encode " .. kind)
  local parts = {}
  if vim.islist(value) then
    for i, item in ipairs(value) do parts[i] = json_encode(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for i, key in ipairs(keys) do parts[i] = json_string(key) .. ":" .. json_encode(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- A TOML basic string. Raw control characters are not allowed in one.
local TOML_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function toml_string(s)
  return '"' .. s:gsub('[%z\1-\31\127"\\]', function(c)
    return TOML_ESCAPES[c] or ("\\u%04X"):format(c:byte())
  end) .. '"'
end

---The trust hash Codex expects for one command hook: sha256 over the sorted,
---compact JSON of the normalized handler (config/src/fingerprint.rs
---version_for_toml over engine/discovery.rs NormalizedHookIdentity). Exposed
---for :checkhealth and the spec, which pins it against fixed vectors.
---@param event_key string e.g. "user_prompt_submit"
---@param command string the hook's shell command, exactly as injected
---@param timeout integer seconds, as injected (Codex hashes the normalized value)
---@return string "sha256:<hex>"
function M.codex_trust_hash(event_key, command, timeout)
  local identity = {
    event_name = event_key,
    hooks = { { type = "command", command = command, timeout = timeout, async = false } },
  }
  return "sha256:" .. vim.fn.sha256(json_encode(identity))
end

---The `--settings` value for native Claude: UserPromptSubmit waits for the
---baseline (bounded), SessionStart only reports the session and runs async.
---Exec form (`args`), so no shell ever re-parses the path.
---@return string json
function M.claude_settings()
  local wait = require("ai.review.config").get().hook_wait_ms
  local script = M.script()
  local function handler(event, extra)
    return vim.tbl_extend("error", { type = "command", command = script, args = { "claude", event, tostring(wait) } }, extra)
  end
  return json_encode({
    hooks = {
      UserPromptSubmit = { { hooks = { handler("submit", { timeout = hook_timeout(wait) }) } } },
      SessionStart = { { hooks = { handler("session", { async = true }) } } },
    },
  })
end

---The `-c` value for native Codex: one UserPromptSubmit hook plus its trust
---state in the same table, so Codex runs it without asking for review and
---never writes ~/.codex/config.toml. Codex runs the command through a shell.
---@return string toml `hooks={...}`
function M.codex_override()
  local wait = require("ai.review.config").get().hook_wait_ms
  local command = vim.fn.shellescape(M.script()) .. " codex submit " .. wait
  local timeout = hook_timeout(wait)
  return ("hooks={UserPromptSubmit=[{hooks=[{type=%s,command=%s,timeout=%d}]}],state={%s={trusted_hash=%s}}}"):format(
    toml_string("command"),
    toml_string(command),
    timeout,
    toml_string(M.CODEX_TRUST_KEY),
    toml_string(M.codex_trust_hash("user_prompt_submit", command, timeout))
  )
end

local warned = {}

local function warn(msg)
  if warned[msg] then return end
  warned[msg] = true
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "AI review" }) end)
end

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---ai.review.rounds, if this config has it. Absent, events are acknowledged and
---dropped; present but broken, require raises and the caller reports it.
local function rounds()
  local mod = package.loaded["ai.review.rounds"]
  if mod == nil and #vim.loader.find("ai.review.rounds") > 0 then mod = require("ai.review.rounds") end
  return type(mod) == "table" and type(mod.native_event) == "function" and mod or nil
end

---@class ai.review.NativeEvent
---@field agent "claude"|"codex"
---@field event "submit"|"session"
---@field payload table the hook's decoded JSON input (session_id, cwd, ...)
---@field gave_up fun(): boolean has the script stopped waiting? Fast-event safe.
---@field done fun() release the waiting script; idempotent, fast-event safe

---Called over RPC from scripts/agent-hook, so it has to answer at once: the
---script is holding the agent's prompt. It reads the payload, acknowledges, and
---hands the event to `ai.review.rounds.native_event` on the next tick.
---
---A submit stays held until that handler calls `done` (once the baseline's tree
---is written) or the script's wait runs out. The script deletes the payload when
---it stops waiting, which is how `gave_up` knows the baseline came too late, and
---how a request that only arrives after that is recognised as missed. A session
---event is released here: there is nothing to wait for.
---
---Events carrying `agent_id` (a Claude subagent or teammate, a Codex spawned
---thread) are dropped: they belong to the parent conversation's turn.
---@param agent string
---@param event string
---@param payload_path string
---@param done_path string
---@return string status, for the script's (discarded) stdout
function M.event(agent, event, payload_path, done_path)
  if not (ROUTES[agent] and ROUTES[agent][event]) or type(payload_path) ~= "string" or type(done_path) ~= "string" then
    return "error:usage"
  end

  local released = false
  local function done()
    if released then return end
    released = true
    -- Only while the script still waits: once it gave up, the file would be
    -- left behind in $TMPDIR. A script that gives up between the check and the
    -- touch is caught by the second check.
    if not exists(payload_path) then return end
    local fd = vim.uv.fs_open(done_path, "w", tonumber("600", 8))
    if fd then vim.uv.fs_close(fd) end
    if not exists(payload_path) then os.remove(done_path) end
  end

  -- Read per event, so switching a source off at runtime takes effect at once,
  -- even for an agent started with the hook injected.
  if not require("ai.review.config").get().sources[agent] then
    done()
    return "disabled"
  end

  local file = io.open(payload_path, "r")
  if not file then
    -- The script gave up before this request was served: Nvim was busy for the
    -- whole wait. The prompt has gone ahead with no baseline in front of it.
    if event == "submit" then
      local label = require("ai.config").providers[agent].label
      vim.schedule(function()
        vim.notify(("Missed a %s prompt submit (Nvim was busy): if it was a prompt of yours, it has no review baseline")
          :format(label),
          vim.log.levels.WARN, { title = "AI review" })
      end)
    end
    return "missed"
  end
  local raw = file:read("*a")
  file:close()

  local ok, payload = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not ok or type(payload) ~= "table" then
    done()
    return "error:payload"
  end
  if payload.agent_id ~= nil then
    done()
    return "ignored"
  end
  if event == "session" then done() end

  vim.schedule(function()
    local fine, err = pcall(function()
      local handler = rounds()
      if not handler then return done() end
      handler.native_event({
        agent = agent,
        event = event,
        payload = payload,
        done = done,
        gave_up = function() return not exists(payload_path) end,
      })
    end)
    if not fine then
      done()
      warn("Agent hook receiver failed: " .. tostring(err))
    end
  end)
  return "ok"
end

return M
