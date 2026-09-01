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

local calls = {}
local pending = {}
local function run(command, callback)
  calls[#calls + 1] = command
  pending[#pending + 1] = callback
end

local function complete(result)
  local callback = table.remove(pending, 1)
  t.ok(callback ~= nil, "a macism operation is pending")
  callback(result)
end

local state = input_method._new({
  command = "macism",
  default_source = "com.apple.keylayout.US",
  run = run,
})

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

-- A failed restore invalidates the source cache. If the user manually picks a
-- CJK source afterwards, the next Normal transition must still issue the
-- English switch instead of trusting the stale pre-restore cache.
local restore_calls = {}
local restore_pending = {}
local restore_state = input_method._new({
  command = "macism",
  default_source = "com.apple.keylayout.US",
  run = function(command, callback)
    restore_calls[#restore_calls + 1] = command
    restore_pending[#restore_pending + 1] = callback
  end,
})
local function restore_complete(result)
  local callback = table.remove(restore_pending, 1)
  t.ok(callback ~= nil, "a restore-edge macism operation is pending")
  callback(result)
end
restore_state.normal(true)
restore_complete({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
restore_complete({ code = 0, stdout = "" })
restore_state.input()
restore_complete({ code = 1, stdout = "" })
restore_state.normal()
t.eq(restore_calls[4], { "macism", "com.apple.keylayout.US" },
  "Normal mode retries English after a failed input-source restore")
restore_complete({ code = 0, stdout = "" })

-- The optional wait is a third argument only on source switches; queries stay
-- argument-free so macism can still report the current source.
local wait_calls = {}
local wait_state = input_method._new({
  command = "macism",
  default_source = "com.apple.keylayout.ABC",
  wait_time = 0,
  run = function(command, callback)
    wait_calls[#wait_calls + 1] = command
    callback({ code = 0, stdout = "com.sogou.inputmethod.sogou.pinyin\n" })
  end,
})
wait_state.normal(true)
t.eq(wait_calls[1], { "macism" }, "the wait setting is not passed to a source query")
t.eq(wait_calls[2], { "macism", "com.apple.keylayout.ABC", "0" },
  "the wait setting is passed to a source switch")
wait_state.input()
t.eq(wait_calls[3], { "macism", "com.sogou.inputmethod.sogou.pinyin", "0" },
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

t.done()
