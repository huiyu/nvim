-- @file completion for the agent prompt buffer (lua/ai/mention.lua).
--
-- The blink.cmp plumbing (menu, fuzzy ranking, accept) is blink's own concern
-- and is not exercised here. What matters in-process is the source contract:
-- which cursor positions count as an @-mention, that candidates come from the
-- project root and follow the query, and that a machine with none of the
-- listers still gets silence instead of an error -- the prompt buffer must
-- never break over an optional binary.
local t = dofile("tests/helper.lua")
local mention = require("ai.mention")

-- Specs run from the repository root, so the project files the source should
-- offer are this config's own.
local source = mention.new()

t.eq(source:get_trigger_characters(), { "@" }, "the source triggers on @")

---Drive one completion request synchronously.
---@param line string
---@param col integer? byte col before which the cursor sits (defaults to #line)
---@return table? response
local function complete(line, col)
  local response
  source:get_completions(
    { line = line, cursor = { 1, col or #line } },
    function(res) response = res end
  )
  vim.wait(2000, function() return response ~= nil end)
  return response
end

---@param response table?
---@param path string
---@return table? item
local function find_item(response, path)
  for _, item in ipairs(response and response.items or {}) do
    if item.label == path then return item end
  end
end

-- UC-1: `@` plus a fragment offers project files, and accepting inserts
-- `@<relative path>` by replacing the whole token from the `@` on.
local res = complete("see @edit")
local item = find_item(res, "lua/ai/editor.lua")
t.ok(item ~= nil, "UC-1: '@edit' offers lua/ai/editor.lua")
if item then
  t.eq(item.textEdit.newText, "@lua/ai/editor.lua", "UC-1: accepting inserts the @-prefixed path")
  t.eq(item.textEdit.range, {
    start = { line = 0, character = 4 },
    ["end"] = { line = 0, character = 9 },
  }, "UC-1: the edit replaces from the @ to the cursor")
end

-- The query narrows over the full path, slashes included, the way the TUI's
-- own finder does -- blink's keyword only reaches back to the last slash.
res = complete("@tests/run")
t.ok(find_item(res, "tests/run.sh") ~= nil, "UC-1: a query may cross a slash")
t.ok(find_item(res, "init.lua") == nil, "UC-1: files not matching the query are dropped")

-- Ignored files stay out: the listers all respect .gitignore.
res = complete("@lazy")
t.ok(find_item(res, "lazy-lock.json") ~= nil, "UC-1: tracked files are offered")
res = complete("@.DS_Store")
t.ok(res ~= nil and #res.items == 0, "UC-1: gitignored files are not offered")

-- A bare `@` offers everything, so the menu opens the moment the trigger fires.
res = complete("@")
t.ok(res ~= nil and #res.items > 0, "UC-1: a bare @ opens with candidates")

-- CJK text directly before the @ is the normal case in a Chinese prompt; a
-- word character there means an email or handle instead.
res = complete("看看@init")
t.ok(find_item(res, "init.lua") ~= nil, "UC-1: @ right after CJK text still completes")
local at = ("看看@init"):find("@", 1, true)
if find_item(res, "init.lua") then
  t.eq(find_item(res, "init.lua").textEdit.range.start.character, at - 1,
    "UC-1: the range's byte offset survives multibyte text before the @")
end
res = complete("mail jeff@gmail")
t.ok(res ~= nil and #res.items == 0, "UC-1: an email address is not a mention")
res = complete("no mention here")
t.ok(res ~= nil and #res.items == 0, "UC-1: no @ token means no candidates")

-- UC-2: with no usable lister (no git repo, no fd, no rg) the source stays
-- silent instead of erroring: absent binaries are skipped, failing ones fall
-- through.
local real_commands = mention._commands
mention._commands = {
  { "definitely-not-a-command-xyz" }, -- not executable: must be skipped
  { "false" },                        -- executable but failing: must fall through
}
mention._drop_cache()
res = complete("@edit")
t.ok(res ~= nil and #res.items == 0, "UC-2: no lister available degrades to silence")
mention._commands = real_commands
mention._drop_cache()

-- UC-R1: the provider is registered but gated, so ordinary buffers never see
-- it -- only a buffer the editor marked as an agent prompt.
local providers = require("blink.cmp.config").sources.providers
t.ok(providers.ai_mention ~= nil, "UC-R1: the blink provider exists")
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(scratch)
t.ok(not providers.ai_mention.enabled(), "UC-R1: an ordinary buffer does not enable the source")
vim.b[scratch].ai_prompt = true
t.ok(providers.ai_mention.enabled(), "UC-R1: the prompt-buffer mark enables it")

t.done()
