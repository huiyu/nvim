local t = dofile("tests/helper.lua")
local input_method = require("util.input_method")

if vim.fn.has("macunix") == 1 and vim.fn.executable("macism") == 1 then
  local registered = vim.api.nvim_get_autocmds({ group = "input_method" })
  t.ok(#registered == 5,
    "input-method events register during init even before a UI attaches")
end

t.eq(input_method._source_from_enabled_layouts({
  { InputSourceKind = "Input Mode", ["Input Mode"] = "com.sogou.inputmethod.pinyin" },
  { InputSourceKind = "Keyboard Layout", ["KeyboardLayout Name"] = "ABC" },
}), "com.apple.keylayout.ABC", "the enabled keyboard layout produces a real macism source ID")

-- AppleEnabledInputSources is in the user's own order, so document order alone
-- would put Normal mode on a layout that cannot type `d`, `w` or `:`.
t.eq(input_method._source_from_enabled_layouts({
  { InputSourceKind = "Keyboard Layout", ["KeyboardLayout Name"] = "Russian" },
  { InputSourceKind = "Keyboard Layout", ["KeyboardLayout Name"] = "ABC" },
}), "com.apple.keylayout.ABC", "a Latin layout wins over an earlier non-Latin one")
t.eq(input_method._source_from_enabled_layouts({
  { InputSourceKind = "Keyboard Layout", ["KeyboardLayout Name"] = "Russian" },
}), "com.apple.keylayout.Russian",
  "the only enabled layout is still used when no Latin one exists")
t.eq(input_method._source_from_enabled_layouts({
  { InputSourceKind = "Input Mode", ["Input Mode"] = "com.sogou.inputmethod.pinyin" },
}), nil, "an input method alone yields no keyboard layout")
t.eq(input_method._command_succeeded({
  code = 0,
  stdout = "Input source com.apple.keylayout.US does not exist!\n",
}), false, "macism's zero-exit invalid-source response is treated as a failure")
t.eq(input_method._wait_time_arg("0"), "0", "zero disables macism's focus-stealing workaround")
t.eq(input_method._wait_time_arg(" 100 "), "100", "a custom macism wait is normalized")
t.eq(input_method._wait_time_arg("fast"), nil, "an invalid macism wait falls back to its default")

--- A state machine over a stand-in macism. Each operation waits until
--- `complete` answers it, in order -- or, given `opts.answer`, is answered at
--- once with what that returns.
local function harness(opts)
  opts = opts or {}
  local h = { calls = {}, pending = {} }
  h.state = input_method._new({
    command = "macism",
    default_source = opts.default_source or "com.apple.keylayout.US",
    wait_time = opts.wait_time,
    run = function(command, callback)
      h.calls[#h.calls + 1] = command
      if opts.answer then
        callback(opts.answer())
      else
        h.pending[#h.pending + 1] = callback
      end
    end,
  })
  function h.complete(result)
    local callback = table.remove(h.pending, 1)
    t.ok(callback ~= nil, "a macism operation is pending")
    callback(result)
  end
  return h
end

local main = harness()
local state, calls, complete = main.state, main.calls, main.complete

-- Startup captures whichever source preceded Nvim, then switches to English.
state.normal(true)
t.eq(calls, { { "macism" } }, "startup queries the current input source")
complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
t.eq(state.previous(), "com.sogou.inputmethod.sogou.pinyin",
  "startup preserves the Chinese input source")
t.eq(calls[2], { "macism", "com.apple.keylayout.US" },
  "Normal mode switches to the detected English layout")
complete({ code = 0, stdout = "" })

-- Insert restores the captured source. Leaving Insert captures a user-selected
-- replacement before returning to English.
state.input()
t.eq(calls[3], { "macism", "com.sogou.inputmethod.sogou.pinyin" },
  "Insert mode restores the previous source")
complete({ code = 0, stdout = "" })
state.normal()
t.eq(calls[4], { "macism" }, "leaving a ready input mode queries its current source")
complete({ code = 0, stdout = "com.apple.inputmethod.SCIM.ITABC\n" })
t.eq(state.previous(), "com.apple.inputmethod.SCIM.ITABC",
  "a source selected during Insert becomes the next source to restore")
t.eq(calls[5], { "macism", "com.apple.keylayout.US" },
  "leaving Insert returns to English")
complete({ code = 0, stdout = "" })

-- A rapid Esc/i sequence must not let a stale English switch win. The query
-- result is still useful: it is the source that was active before Esc.
state.input()
complete({ code = 0, stdout = "" })
state.normal()
t.eq(calls[7], { "macism" }, "rapid-transition setup captures the input source")
state.input()
complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
t.eq(state.previous(), "com.sogou.inputmethod.sogou.pinyin",
  "a query that finishes after re-entering input still preserves its source")
t.eq(#calls, 7,
  "the stale Normal request issues no switch after input mode becomes current")

-- If capture fails, stay put instead of switching to English without a value
-- that can be restored later.
state.normal()
t.eq(calls[8], { "macism" }, "leaving input queries before switching")
complete({ code = 1, stdout = "" })
t.eq(#calls, 8, "a failed capture does not issue a destructive switch")

-- A Normal-mode escape chord captures a source selected manually in Normal,
-- switches it off without changing modes, and owns exactly one restoration.
-- Repeats during the query, during the switch, and after the switch must not
-- overwrite the captured CJK source with the now-active English layout.
local chord = harness()
chord.state.normal(true)
chord.complete({ code = 0, stdout = "com.apple.keylayout.US\n" })
chord.state.normal_source()
t.eq(chord.calls[2], { "macism" }, "the Normal key queries a manually selected source")
chord.state.normal_source()
t.eq(#chord.calls, 2, "a repeated Normal key does not duplicate a pending query")
chord.complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
t.eq(chord.calls[3], { "macism", "com.apple.keylayout.US" },
  "the Normal key switches a captured CJK source to English")
chord.state.normal_source()
t.eq(#chord.calls, 3, "a repeated Normal key does not interrupt its pending switch")
chord.complete({ code = 0, stdout = "" })
chord.state.normal_source()
t.eq(chord.calls[4], { "macism" },
  "a settled repeat checks for a source manually selected since the last press")
chord.complete({ code = 0, stdout = "com.apple.keylayout.US\n" })
t.eq(chord.state.previous(), "com.sogou.inputmethod.sogou.pinyin",
  "a repeat on English does not overwrite the source awaiting restoration")
chord.state.input()
t.eq(chord.calls[5], { "macism", "com.sogou.inputmethod.sogou.pinyin" },
  "Insert restores the source that the Normal key actually switched away")
chord.complete({ code = 0, stdout = "" })

-- Entering Insert before the explicit English switch completes must wait for
-- that real switch and then restore it; the late English result must not win.
local rapid = harness()
rapid.state.normal(true)
rapid.complete({ code = 0, stdout = "com.apple.keylayout.US\n" })
rapid.state.normal_source()
rapid.complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
rapid.state.input()
rapid.complete({ code = 0, stdout = "" })
t.eq(rapid.calls[4], { "macism", "com.sogou.inputmethod.sogou.pinyin" },
  "Insert restores after an in-flight Normal-key switch succeeds")
rapid.complete({ code = 0, stdout = "" })

local failed_key_results = {
  { code = 0, stdout = "com.apple.keylayout.US\n" },
  { code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" },
  { code = 1, stdout = "" },
}
local failed_key = harness({ answer = function() return table.remove(failed_key_results, 1) end })
failed_key.state.normal(true)
failed_key.state.normal_source()
failed_key.state.input()
t.eq(#failed_key.calls, 3,
  "Insert does not restore when the Normal-key switch failed")

-- If the chord finds Normal mode already on English, it did not close an input
-- method and must not manufacture a restoration on the next InsertEnter.
local inactive = harness()
inactive.state.normal(true)
inactive.complete({ code = 0, stdout = "com.apple.keylayout.US\n" })
inactive.state.normal_source()
inactive.complete({ code = 0, stdout = "com.apple.keylayout.US\n" })
inactive.state.input()
t.eq(#inactive.calls, 2,
  "Insert leaves the current source alone when the Normal key closed nothing")

-- A failed restore invalidates the source cache. If the user manually picks a
-- CJK source afterwards, the next Normal transition must still issue the
-- English switch instead of trusting the stale pre-restore cache.
local restore = harness()
restore.state.normal(true)
restore.complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
restore.complete({ code = 0, stdout = "" })
restore.state.input()
restore.complete({ code = 1, stdout = "" })
restore.state.normal()
t.eq(restore.calls[4], { "macism", "com.apple.keylayout.US" },
  "Normal mode retries English after a failed input-source restore")
restore.complete({ code = 0, stdout = "" })

-- The optional wait is a third argument only on source switches; queries stay
-- argument-free so macism can still report the current source.
local waiting = harness({
  default_source = "com.apple.keylayout.ABC",
  wait_time = 0,
  answer = function() return { code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" } end,
})
waiting.state.normal(true)
t.eq(waiting.calls[1], { "macism" }, "the wait setting is not passed to a source query")
t.eq(waiting.calls[2], { "macism", "com.apple.keylayout.ABC", "0" },
  "the wait setting is passed to a source switch")
waiting.state.input()
t.eq(waiting.calls[3], { "macism", "com.sogou.inputmethod.sogou.pinyin", "0" },
  "restoring a CJK source can disable the temporary focus window")

local detected = 0
local source, origin = input_method._resolve_default_source(" com.apple.keylayout.ABC ", function()
  detected = detected + 1
end)
t.eq(source, "com.apple.keylayout.ABC", "the environment source is trimmed and preferred")
t.eq(origin, "NVIM_ENGLISH_INPUT_SOURCE", "health can report the environment origin")
t.eq(detected, 0, "macOS defaults are not read when the environment is configured")

source, origin = input_method._resolve_default_source(nil, function()
  return "com.apple.keylayout.US\n"
end)
t.eq(source, "com.apple.keylayout.US", "macOS detection provides the fallback source")
t.eq(origin, "macOS keyboard layout", "health can report the fallback origin")

---------------------------------------------------------------------------
-- The escape chords: <C-]> and <C-\> leave input in every mode, and in
-- Normal mode ask for the Normal input source.
---------------------------------------------------------------------------
do
  local function mapping(lhs, mode)
    return vim.fn.maparg(lhs, mode, false, true)
  end

  for _, lhs in ipairs({ "<C-]>", "<C-\\>" }) do
    local insert = mapping(lhs, "i")
    t.eq(insert.rhs, "<Esc>", lhs .. " leaves Editor input through Escape")
    t.eq(insert.desc, "Exit input mode", lhs .. " Insert mapping is discoverable")

    local terminal = mapping(lhs, "t")
    t.eq(terminal.rhs, "<C-\\><C-n>", lhs .. " reaches terminal-Normal mode")
    t.eq(terminal.desc, "Exit input mode", lhs .. " terminal mapping is discoverable")

    -- Visual too: a selection made with an input method still active needs the
    -- same exit, and leaving it to the global Normal-mode map would clear the
    -- highlight instead of dropping the selection.
    local visual = mapping(lhs, "x")
    t.eq(visual.rhs, "<Esc>", lhs .. " leaves a Visual selection")
    t.eq(visual.desc, "Exit selection mode", lhs .. " Visual mapping is discoverable")
  end

  for _, lhs in ipairs({ "<C-]>", "<C-\\>" }) do
    local normal = mapping(lhs, "n")
    t.ok(type(normal.callback) == "function",
      "Normal-mode " .. lhs .. " uses the input-source-aware Escape callback")
    t.eq(normal.desc, "Escape with Normal input source",
      "Normal-mode " .. lhs .. " documents its input-source behavior")
  end

  local original_ensure = input_method.ensure_normal_source
  local source_requests = 0
  input_method.ensure_normal_source = function()
    source_requests = source_requests + 1
    return true
  end
  local mode_before = vim.api.nvim_get_mode().mode
  mapping("<C-\\>", "n").callback()
  input_method.ensure_normal_source = original_ensure
  t.eq(source_requests, 1, "the Normal Escape requests the Normal input source")
  t.eq(vim.api.nvim_get_mode().mode, mode_before,
    "the Normal Escape does not change modes")

  -- `help` and `man` navigate with <C-]>, so the global Escape steps aside there.
  -- maparg reports the mapping of the *current* buffer, so the scratch buffer has
  -- to be entered rather than just created.
  local origin_buf = vim.api.nvim_get_current_buf()
  for _, ft in ipairs({ "help", "man" }) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = ft

    local restored = mapping("<C-]>", "n")
    t.eq(restored.buffer, 1, ft .. " restores <C-]> buffer-locally")
    t.eq(restored.rhs, "<C-]>", ft .. " follows the tag under the cursor")
    t.eq(restored.noremap, 1, ft .. " reaches the builtin, not the global Escape")
    -- The Escape half is not lost with the tag jump.
    t.ok(type(mapping("<C-\\>", "n").callback) == "function",
      ft .. " keeps <C-\\> as the input-source-aware Escape")

    vim.api.nvim_set_current_buf(origin_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- An ordinary buffer is unaffected: the global Escape is still what answers.
  t.eq(mapping("<C-]>", "n").buffer, 0,
    "an ordinary buffer keeps the global repeatable Escape")

  local comma_terminal = mapping("<C-,>", "t")
  t.ok(comma_terminal.rhs:find("<C-\\><C-n>", 1, true) ~= nil,
    "terminal Ctrl-comma first leaves terminal input")
  t.ok(comma_terminal.rhs:find("WindowFocusEditor", 1, true) ~= nil,
    "terminal Ctrl-comma reaches the editor in one press")

  -- Ctrl-comma needs the extended-key protocol. se is the plain-key twin
  -- for the terminals that never negotiate it, so the editor jump stays reachable
  -- where the chord cannot be sent at all.
  --
  -- Entries with an RHS are real keymaps once which-key's scheduled loader has
  -- run. Specs execute before the normal VimEnter point, so fire that lifecycle
  -- event explicitly before asserting the live mapping.
  vim.cmd("Lazy! load which-key.nvim")
  vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
  vim.wait(100, function() return vim.fn.maparg("se", "n") ~= "" end)

  local live_editor = mapping("se", "n")
  t.ok(type(live_editor.rhs) == "string"
    and live_editor.rhs:find("WindowFocusEditor", 1, true) ~= nil,
    "se is the live plain-key fallback for the editor jump")
end

t.done()
