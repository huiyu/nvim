-- Keep Normal mode on a macOS keyboard layout while preserving the input
-- method used for text entry. macism performs the system switch; this module
-- owns only Neovim's mode transitions and the previous-source state.
local M = {}

local env_name = "NVIM_ENGLISH_INPUT_SOURCE"
local wait_env_name = "NVIM_MACISM_WAIT_TIME_MS"
local defaults_key = "AppleCurrentKeyboardLayoutInputSourceID"
local controller
local registered

local function source_id(value)
  if type(value) ~= "string" then return nil end
  value = vim.trim(value)
  return value ~= "" and value or nil
end

---Resolve the target keyboard layout, preferring an explicit environment value.
---@param configured string|nil
---@param detect fun(): string|nil
---@return string|nil source
---@return string|nil origin
function M._resolve_default_source(configured, detect)
  local source = source_id(configured)
  if source then return source, env_name end

  source = source_id(detect())
  if source then return source, "macOS keyboard layout" end
  return nil, nil
end

-- Latin layouts that can type Nvim's command set. This is a preference, not a
-- filter: an enabled layout outside the list still beats no layout at all.
local latin_layouts = {
  ABC = true, US = true, USExtended = true, Colemak = true, Dvorak = true,
  British = true, Australian = true, Canadian = true, Irish = true,
}

---Derive a macism source ID from a simple enabled keyboard-layout name.
---
---`AppleEnabledInputSources` is in the user's own order, so the first keyboard
---layout in it can be Russian or Greek. Normal mode on a non-Latin layout is
---the one outcome worse than not switching at all -- `d`, `w` and `:` would
---stop reaching Nvim -- so a Latin layout wins over document order.
---@param sources table
---@return string|nil
function M._source_from_enabled_layouts(sources)
  local fallback
  for _, item in ipairs(sources) do
    local name = item["KeyboardLayout Name"]
    if item.InputSourceKind == "Keyboard Layout"
        and type(name) == "string"
        and name:match("^[%w]+$") then
      if latin_layouts[name] then return "com.apple.keylayout." .. name end
      fallback = fallback or ("com.apple.keylayout." .. name)
    end
  end
  return fallback
end

local function detect_keyboard_layout()
  if vim.fn.has("macunix") ~= 1 then return nil end

  local home = vim.env.HOME
  if home and vim.fn.executable("/usr/bin/plutil") == 1 then
    local result = vim.system({
      "/usr/bin/plutil",
      "-extract",
      "AppleEnabledInputSources",
      "json",
      "-o",
      "-",
      vim.fs.joinpath(home, "Library/Preferences/com.apple.HIToolbox.plist"),
    }, { text = true }):wait()
    if result.code == 0 then
      local ok, sources = pcall(vim.json.decode, result.stdout)
      if ok and type(sources) == "table" then
        local source = M._source_from_enabled_layouts(sources)
        if source then return source end
      end
    end
  end

  if vim.fn.executable("/usr/bin/defaults") ~= 1 then return nil end
  local result = vim.system({
    "/usr/bin/defaults",
    "read",
    "com.apple.HIToolbox",
    defaults_key,
  }, { text = true }):wait()
  return result.code == 0 and result.stdout or nil
end

---Return the keyboard layout used outside text-entry modes.
---@return string|nil source
---@return string|nil origin
function M.default_source()
  return M._resolve_default_source(vim.env[env_name], detect_keyboard_layout)
end

function M._command_succeeded(result)
  local output = (result.stdout or "") .. (result.stderr or "")
  return result.code == 0 and not output:find("does not exist", 1, true)
end

---Normalize macism's optional TemporaryWindow wait argument.
---@param value string|number|nil
---@return string|nil
function M._wait_time_arg(value)
  if value == nil then return nil end
  value = source_id(tostring(value))
  return value and value:match("^%d+$") and value or nil
end

local function system_run(command, callback)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function() callback(result) end)
  end)
end

---Create the serialized input-source state machine.
---Exposed for headless tests; normal configuration should call setup().
---@param opts { command: string, default_source: string, wait_time: string|number|nil, run: fun(command: string[], callback: fun(result: table)) }
---@return table
function M._new(opts)
  local command = assert(opts.command)
  local default = assert(source_id(opts.default_source))
  local wait_time = M._wait_time_arg(opts.wait_time)
  local run = assert(opts.run)

  local generation = 0
  local settled = -1
  local busy = false
  local mode
  local previous = default
  local known_source
  local input_ready = false
  local capture_requested = false

  local reconcile

  local function finish(token)
    if token == generation then settled = token end
    reconcile()
  end

  local function switch_to(target, token, applied)
    if known_source == target then
      if applied then applied(true) end
      finish(token)
      return
    end

    busy = true
    local args = { command, target }
    if wait_time then args[#args + 1] = wait_time end
    run(args, function(result)
      busy = false
      local ok = M._command_succeeded(result)
      -- A failed switch makes the cached source untrustworthy: the user may
      -- select another input method before the next mode transition. Clearing
      -- it forces Normal mode to issue the English switch instead of falsely
      -- short-circuiting on the last known value.
      known_source = ok and target or nil

      if token == generation then
        if applied then applied(ok) end
        finish(token)
      else
        reconcile()
      end
    end)
  end

  reconcile = function()
    if busy or settled == generation or not mode then return end
    local token = generation

    if mode == "normal" and capture_requested then
      capture_requested = false
      busy = true
      run({ command }, function(result)
        busy = false
        local current = result.code == 0 and source_id(result.stdout) or nil
        if current then
          previous = current
          known_source = current
        end

        if token == generation and mode == "normal" then
          if current then
            switch_to(default, token)
          else
            -- Do not switch when the source could not be captured: losing the
            -- value needed for restoration is worse than leaving Normal mode
            -- on the current input method for this transition.
            finish(token)
          end
        else
          reconcile()
        end
      end)
      return
    end

    if mode == "normal" then
      switch_to(default, token)
      return
    end

    switch_to(previous, token, function(ok)
      if token == generation and mode == "input" then input_ready = ok end
    end)
  end

  local state = {}

  ---Enter Normal/Terminal-Normal mode.
  ---@param initial boolean|nil capture the source that preceded Nvim startup
  function state.normal(initial)
    generation = generation + 1
    mode = "normal"
    settled = -1
    capture_requested = initial == true or input_ready
    input_ready = false
    reconcile()
  end

  ---Enter Insert or terminal-input mode and restore the captured source.
  function state.input()
    generation = generation + 1
    mode = "input"
    settled = -1
    capture_requested = false
    input_ready = false
    reconcile()
  end

  ---Return the most recently captured text-entry source.
  ---@return string
  function state.previous()
    return previous
  end

  return state
end

---Enable automatic input-source switching for an attached macOS UI.
---@return boolean enabled
function M.setup()
  if registered then return true end
  if vim.fn.has("macunix") ~= 1 then return false end
  if vim.fn.executable("macism") ~= 1 then return false end
  registered = true

  -- Resolving the layout shells out to plutil and possibly `defaults read`.
  -- That work is deferred to the first UI event rather than done here: setup()
  -- runs from init.lua, where headless Nvim -- the spec suite, a git hook, a
  -- `--headless +qa` check -- would pay for a feature it can never use. `false`
  -- records a resolution that already failed, so a machine without a detectable
  -- layout does not re-shell on every InsertEnter.
  local function resolve()
    if controller == nil then
      local default = M.default_source()
      controller = default and M._new({
        command = "macism",
        default_source = default,
        wait_time = vim.env[wait_env_name],
        run = system_run,
      }) or false
    end
    return controller or nil
  end

  local function with_ui(callback)
    return function()
      -- During init.lua the terminal UI has not attached yet. Check at event
      -- time so startup can register the feature without making headless Nvim
      -- mutate the desktop's global input source.
      if #vim.api.nvim_list_uis() == 0 then return end
      local state = resolve()
      if state then callback(state) end
    end
  end

  local group = vim.api.nvim_create_augroup("input_method", { clear = true })
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = with_ui(function(state) state.normal(true) end),
    once = true,
    desc = "Capture input source and use the English keyboard layout",
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "TermLeave" }, {
    group = group,
    callback = with_ui(function(state) state.normal() end),
    desc = "Remember text-entry input source and use the English keyboard layout",
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "TermEnter" }, {
    group = group,
    callback = with_ui(function(state) state.input() end),
    desc = "Restore the previous text-entry input source",
  })

  return true
end

return M
