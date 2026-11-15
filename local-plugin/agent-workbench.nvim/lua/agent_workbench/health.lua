local M = {}
local health = vim.health
local function section(name, check)
  health.start(name)
  local ok, err = pcall(check)
  if not ok then health.error("this check failed: " .. tostring(err)) end
end

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function toml_strings(s)
  local shape, strings, i = {}, {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c ~= '"' then
      shape[#shape + 1], i = c, i + 1
    else
      local buf, j = {}, i + 1
      while true do
        local ch = s:sub(j, j)
        if ch == "" then return nil, {} end
        if ch == '"' then break end
        if ch == "\\" then
          local e = s:sub(j + 1, j + 1)
          local hex = e == "u" and s:sub(j + 2, j + 5):match("^%x%x%x%x$")
          if TOML_UNESCAPE[e] then
            buf[#buf + 1], j = TOML_UNESCAPE[e], j + 2
          elseif hex then
            buf[#buf + 1], j = vim.fn.nr2char(tonumber(hex, 16)), j + 6
          else
            return nil, {}
          end
        else
          buf[#buf + 1], j = ch, j + 1
        end
      end
      strings[#strings + 1] = table.concat(buf)
      shape[#shape + 1], i = "$", j + 1
    end
  end
  return table.concat(shape), strings
end

local CODEX_SHAPE =
  "^hooks={UserPromptSubmit=%[{hooks=%[{type=%$,command=%$,timeout=(%d+)}%]}%],state={%$={trusted_hash=%$}}}$"

-- Each sources.* switch, with the prompts it stops opening rounds.
local SOURCES = {
  { "codex", "native Codex" },
  { "codecompanion_acp", "ACP chats (<leader>an)" },
  { "codecompanion_http", "API chats (<leader>an)" },
}

-- Static checks only: the strings ai.review.hook generates are parsed and
-- compared with what local-plugin/agent-workbench.nvim/scripts/agent-hook and each CLI expect. No agent runs,
-- so whether a CLI then accepts them is left to the hints at the end.
local function check_hooks()
  local hook = require("agent_workbench.review.hook")
  local review = require("agent_workbench.review.settings").get()
  local wait = review.hook_wait_ms
  local script = hook.script()
  local no_round = "the native agents' prompt hooks cannot run, so their prompts open no review round"
  if vim.fn.executable(script) == 1 then
    health.ok("agent-hook executable — the native agents' prompt hooks run it")
  elseif vim.uv.fs_stat(script) then
    health.warn(("%s is not executable — %s"):format(script, no_round), { "chmod +x " .. vim.fn.shellescape(script) })
  else
    health.warn(("%s is missing — %s"):format(script, no_round),
      { "It belongs to this config: restore it from the repository" })
  end
  if vim.fn.executable("nvim") ~= 1 then
    health.warn("nvim is not on PATH — agent-hook calls back into this Nvim with `nvim --server`, "
      .. "so native prompts open no review round", { "Start Nvim with its directory on PATH" })
  end

  -- Codex runs its hook through a shell, so the command is one string.
  local shape, strings = toml_strings(hook.codex_override())
  local timeout = shape and tonumber(shape:match(CODEX_SHAPE))
  local command = vim.fn.shellescape(script) .. " codex submit " .. wait
  if not (timeout and strings[1] == "command" and strings[2] == command and strings[3] == hook.CODEX_TRUST_KEY) then
    health.error("Codex's -c hooks= value is not the agent-hook entry it should carry — "
      .. "native Codex prompts open no review round", { "tests/agent_hook_spec.lua pins it" })
  else
    local want = hook.codex_trust_hash("user_prompt_submit", command, timeout)
    if strings[4] == want and want:match("^sha256:" .. ("%x"):rep(64) .. "$") then
      health.ok(("Codex -c hooks= is valid: UserPromptSubmit waits up to %d ms (hook timeout %d s), "
        .. "its trusted_hash matches"):format(wait, timeout))
    else
      health.error(("Codex's trusted_hash %s is not %s, the hash of the command it carries — "
        .. "Codex would not run the hook without a review"):format(tostring(strings[4]), want),
        { "tests/agent_hook_spec.lua pins it" })
    end
  end

  for _, source in ipairs(SOURCES) do
    if review.sources[source[1]] == false then
      health.info(("sources.%s = false — %s prompts open no review round"):format(source[1], source[2]))
    end
  end
  health.info("Not checked here: Claude runs no hook under --bare, with disableAllHooks or allowManagedHooksOnly "
    .. "in managed settings, or in a folder it has not trusted")
  health.info("Not checked here: whether a newer Codex still accepts that hash. "
    .. "Codex's /hooks lists ours under Session flags; Claude's /hooks leaves out --settings hooks, "
    .. "so there <leader>aV naming a Claude session shows SessionStart arrived")
end

local function check_review_settings()
  local config = require("agent_workbench.review.settings")
  local effective, from_user = config.get(), config.overrides()

  -- A non-empty table that is not a list is a group of settings.
  local function is_group(value)
    return type(value) == "table" and next(value) ~= nil and not vim.islist(value)
  end
  local function leaves(node, prefix, out)
    local keys = vim.tbl_keys(node)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local path = prefix == "" and key or prefix .. "." .. key
      if is_group(node[key]) then leaves(node[key], path, out) else out[#out + 1] = path end
    end
    return out
  end
  local function at(node, path)
    for part in path:gmatch("[^.]+") do
      if type(node) ~= "table" then return nil end
      node = node[part]
    end
    return node
  end

  local defaults = config.defaults()
  for _, path in ipairs(leaves(defaults, "", {})) do
    health.info(("%s = %s (%s)"):format(path, vim.inspect(at(effective, path)),
      from_user[path] and "vim.g.ai_review" or "default"))
  end

  -- What vim.g.ai_review asked for and did not get: config.lua warned about
  -- each one when it fell back.
  local user = vim.g.ai_review
  if user ~= nil and type(user) ~= "table" then
    health.warn(("vim.g.ai_review is a %s, not a table — every setting is its default"):format(type(user)))
    return
  end
  if user == nil then return end
  local rejected, trimmed = {}, {}
  local function compare(node, schema, prefix)
    for key, value in pairs(node) do
      local path = prefix == "" and tostring(key) or prefix .. "." .. tostring(key)
      local default = type(schema) == "table" and schema[key] or nil
      if is_group(default) and type(value) == "table" then
        compare(value, default, path)
      elseif not from_user[path] then
        rejected[#rejected + 1] = "vim.g.ai_review." .. path
      elseif type(value) == "table" and #value ~= #(at(effective, path) or {}) then
        trimmed[#trimmed + 1] = "vim.g.ai_review." .. path
      end
    end
  end
  compare(user, defaults, "")
  table.sort(rejected)
  table.sort(trimmed)
  local why = { "An unknown key or a value outside the setting's domain: the \"AI review\" warning names each problem" }
  if #rejected > 0 then
    health.warn("not applied, the default is used instead: " .. table.concat(rejected, ", "), why)
  end
  if #trimmed > 0 then
    health.warn("applied without the entries that are not valid: " .. table.concat(trimmed, ", "), why)
  end
end

local function check_drafts()
  local loc = require("git_review.baseline").locate(vim.fn.getcwd())
  if not loc then health.info("No Git worktree for feedback drafts"); return end
  -- A draft holds feedback only while it is a non-empty file: delivering it,
  -- or deleting every entry, leaves it empty (local-plugin/agent-workbench.nvim/lua/agent_workbench/review/feedback.lua), and
  -- only a non-empty one spares its round from retention (rounds._exempt).
  -- <id>.last-sent.md is the copy of the last delivery, not a draft.
  local dir = vim.fs.dirname(require("agent_workbench.review.rounds").draft_path(loc.toplevel, "unowned"))
  local drafts, sent, conflicts = 0, 0, 0
  if vim.fn.isdirectory(dir) == 1 then
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" and name:match("%.conflict%-?%d*%.md$") then
        conflicts = conflicts + 1
      elseif kind == "file" and name:match("%.last%-sent%.md$") then
        sent = sent + 1
      elseif kind == "file" and name:match("%.md$") then
        local stat = vim.uv.fs_stat(dir .. "/" .. name)
        if stat and stat.size > 0 then drafts = drafts + 1 end
      end
    end
  end
  local copies = sent == 0 and "" or (", %d last-sent %s"):format(sent, sent == 1 and "copy" or "copies")
  health.info(("feedback drafts for this worktree live in %s: %s with feedback%s%s"):format(dir,
    plural(drafts, "draft"), copies, conflicts > 0 and (", " .. plural(conflicts, "conflict file")) or ""))
end
function M.check()
  local ai = require("agent_workbench.state")
  health.start("config: AI backends")
  health.info("Providers, in the order of lua/config/ai.lua; <leader>an lists every available one")
  health.ok(("HTTP key profile %s (%s), :AI key switches it"):format(ai.key.label, ai.key_setting()))

  -- Every part each provider offers. A missing one is a warning: the picker
  -- leaves it out and the rest still work. Only nothing at all is an error.
  local any, label = false, {}
  for _, provider in ipairs(ai.providers) do label[provider.name] = provider.label end
  for _, b in ipairs(ai.backends()) do
    local name = label[b.provider]
    if b.kind == "native" then
      if b.available then
        any = true
        health.ok(("%s found — %s native agent available"):format(b.command, name))
      else
        health.warn(("%s not found — %s native agent unavailable"):format(b.command, name))
      end
    elseif b.kind == "acp" then
      if b.available then
        any = true
        health.ok(("%s found — <leader>an can start %s over ACP"):format(b.command, name))
      else
        health.warn(("%s not found — no %s chat over ACP"):format(b.command, name))
      end
    end -- API chats: the key checks below
  end

  -- The agents' ctrl+g ("edit this prompt in $EDITOR") is pointed at this
  -- wrapper. A non-executable one is not fatal -- ctrl+g falls back to starting
  -- a nested nvim inside the :terminal -- but that failure is silent, so it is
  -- worth surfacing here rather than leaving it to be discovered mid-prompt.
  local wrapper = require("agent_workbench.backend.launch").wrapper()
  if vim.fn.executable(wrapper) == 1 then
    health.ok("agent-editor wrapper executable — ctrl+g edits the TUI prompt in this Nvim")
  else
    health.warn(("%s not executable — ctrl+g will open a nested nvim instead"):format(wrapper),
      { "chmod +x " .. wrapper })
  end

  local function is_set(var) return vim.env[var] ~= nil and vim.env[var] ~= "" end
  for _, name in ipairs(ai.key_names()) do
    local var = ai.key_profiles[name].api_key
    if is_set(var) then
      any = true
      health.ok(("%s found — key profile %s can run API chats and inline/command prompts"):format(var, name))
    elseif name == ai.key.name then
      health.warn(("%s not set — native and ACP chats work; inline edits refuse until it is set"):format(var),
        { "See README.md, API keys" })
    else
      health.info(("%s not set — no %s API chat until it is"):format(var, name))
    end
  end

  if not any then
    health.error("No AI backend is available: no agent CLI, ACP bridge or API key found",
      { "Install codex, or set an NVIM_* API key; see README.md" })
  end

  -- An agent's own variable outranks its subscription login, so an export
  -- meant for something else silently moves the native terminal and ACP chat
  -- onto API billing. Every provider is checked: any of them can be started.
  for _, provider in ipairs(ai.providers) do
    local cli_key = provider.cli_api_key
    if cli_key and is_set(cli_key) then
      health.warn(("%s is set — %s started from this Nvim can bill the API instead of the subscription")
        :format(cli_key, provider.label), { "Unset it unless API billing is intended; Nvim reads NVIM_* keys" })
    elseif cli_key then
      health.ok(("%s not set — %s uses its subscription login"):format(cli_key, provider.label))
    end
  end

  if require("agent_workbench.options").get().integrations.review then
    section("config: review hooks", check_hooks)
    section("config: review settings (vim.g.ai_review)", check_review_settings)
    section("config: review drafts", check_drafts)
  end
end
return M
