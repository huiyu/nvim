-- @file completion for the agent prompt buffer, as a blink.cmp source.
--
-- Both agent TUIs pop a fuzzy file finder on `@` in their own input box. That
-- finder is the CLI's UI, so it cannot follow the prompt through the ctrl+g
-- handoff (lua/ai/editor.lua) -- the buffer that opens here is plain markdown.
-- This source restores the habit: `@` plus a fragment completes project files,
-- and accepting inserts `@<relative path>`.
--
-- What the agent does with the returned text differs per provider: Claude Code
-- parses `@path` back into a real file mention when the prompt is submitted,
-- Codex treats it as a path the agent resolves itself. Both read the file
-- either way, so one insert format serves both.
--
-- Registered in lua/plugin/lsp/cmp.lua, enabled only for buffers the editor
-- marked with vim.b.ai_prompt -- ordinary markdown never sees it.

local M = {}

-- File listers, tried in order until one succeeds. All of them respect
-- .gitignore, which is what makes the candidates match the TUI's own finder.
-- Exposed on the module so tests can simulate a machine that has none.
M._commands = {
  -- --others + --exclude-standard folds in untracked-but-not-ignored files,
  -- which a prompt mentions as often as tracked ones.
  { "git", "ls-files", "--cached", "--others", "--exclude-standard" },
  { "fd", "--type", "f" },
  { "rg", "--files" },
}

-- The menu never needs more than a screenful; the query narrows the rest.
local MAX_ITEMS = 200

-- One listing per burst of keystrokes: is_incomplete below makes blink call
-- get_completions on every typed character, and running `git ls-files` for
-- each of them would be pure waste. The TTL stays short so files the agent
-- just created appear on the next mention.
local CACHE_TTL_MS = 2000

local cache = { root = nil, at = 0, files = nil }

---Forget the cached listing. Tests swap M._commands and must not see files
---from the previous lister.
function M._drop_cache()
  cache = { root = nil, at = 0, files = nil }
end

---Find the @-token the cursor sits in.
---
---A mention starts at an `@` whose preceding character is not word-like, so
---`jeff@gmail` stays an email. The check is byte-based on purpose: any byte of
---a multibyte character fails the word-class match, which is exactly right --
---`看看@init` is a mention, and CJK prompts rarely put a space before the `@`.
---@param line string
---@param col integer 0-based byte column of the cursor
---@return integer? start 1-based byte index of the `@`
---@return string? query text typed after the `@`
local function mention_query(line, col)
  local before = line:sub(1, col)
  local start, query = before:match("()@(%S*)$")
  if not start then return nil end
  if start > 1 and before:sub(start - 1, start - 1):match("[%w._%-]") then return nil end
  return start, query
end

---Case-insensitive subsequence match over the full relative path, slashes
---included -- blink's own keyword stops at the last slash, so the slash-crossing
---part of the TUI finder's behavior has to live here.
---@param path string
---@param query string
---@return boolean
local function matches(path, query)
  if query == "" then return true end
  local p = path:lower()
  local pos = 1
  for i = 1, #query do
    local found = p:find(query:sub(i, i):lower(), pos, true)
    if not found then return false end
    pos = found + 1
  end
  return true
end

---Rank a match: substring hits beat scattered subsequences, earlier and
---shorter beat later and longer.
---@param path string
---@param query string
---@return integer
local function rank(path, query)
  if query == "" then return #path end
  local pos = path:lower():find(query:lower(), 1, true)
  if pos then return pos * 1000 + #path end
  return 1e9 + #path
end

---List project files under `root`, through the first lister that works.
---@param root string
---@param on_done fun(files: string[])
local function list_files(root, on_done)
  if cache.root == root and cache.files and (vim.uv.now() - cache.at) < CACHE_TTL_MS then
    on_done(cache.files)
    return
  end

  local function try(i)
    local cmd = M._commands[i]
    if not cmd then
      -- Nothing worked (not a repo, no fd, no rg): silence, never an error.
      -- The prompt buffer must not break over an optional binary.
      on_done({})
      return
    end
    if vim.fn.executable(cmd[1]) ~= 1 then
      try(i + 1)
      return
    end
    vim.system(cmd, { cwd = root, text = true }, function(res)
      -- Back on the main loop: try() calls vim.fn.*, and on_done builds items.
      vim.schedule(function()
        if res.code ~= 0 or not res.stdout or res.stdout == "" then
          try(i + 1)
          return
        end
        local files = vim.split(res.stdout, "\n", { plain = true, trimempty = true })
        cache = { root = root, at = vim.uv.now(), files = files }
        on_done(files)
      end)
    end)
  end

  try(1)
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
  return { "@" }
end

---@param ctx { line: string, cursor: integer[] }
---@param callback fun(response: table?)
---@return fun()?
function M:get_completions(ctx, callback)
  callback = vim.schedule_wrap(callback)
  -- is_incomplete on both sides: blink then re-queries on every keystroke, so
  -- the filtering below tracks the full @-token instead of blink's keyword.
  local function respond(items)
    callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = items })
  end

  local start, query = mention_query(ctx.line, ctx.cursor[2])
  if not start or not query then
    respond({})
    return
  end

  local canceled = false

  -- The prompt file itself lives in a temp dir; the project the mention should
  -- resolve against is the one this Nvim (and the agent under it) runs in.
  list_files(vim.fn.getcwd(), function(files)
    if canceled then return end

    local matched = {}
    for _, file in ipairs(files) do
      if matches(file, query) then matched[#matched + 1] = file end
    end
    table.sort(matched, function(a, b)
      local ra, rb = rank(a, query), rank(b, query)
      if ra ~= rb then return ra < rb end
      return a < b
    end)

    -- Byte offsets, matching blink's own path source; multibyte text before
    -- the `@` is already counted correctly because `start` is a byte index.
    local range = {
      start = { line = ctx.cursor[1] - 1, character = start - 1 },
      ["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
    }
    local kind = require("blink.cmp.types").CompletionItemKind.File

    local items = {}
    for i = 1, math.min(#matched, MAX_ITEMS) do
      local insert = "@" .. matched[i]
      items[i] = {
        label = matched[i],
        kind = kind,
        insertText = insert,
        textEdit = { newText = insert, range = range },
        -- Keeps our ranking when blink's fuzzy score ties (empty keyword
        -- right after `@` or a `/` ties everything).
        sortText = ("%05d"):format(i),
      }
    end
    respond(items)
  end)

  return function() canceled = true end
end

return M
