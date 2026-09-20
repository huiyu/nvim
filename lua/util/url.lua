local M = {}

-- Include UTF-8 bytes so removing the <cfile> shortcut does not truncate URLs
-- with Unicode hostnames, paths, or query values.
local url_chars = "[%w%-%._~:/?#%[%]@!$&'()*+,;%%=\128-\255]+"
-- CJK and fullwidth punctuation (，。、（）「」“”…) never appear unencoded in a
-- URL, and CJK prose runs straight into a link without a space, so the first
-- such character ends the URL text.
local cjk_punctuation =
  [=[[\u2018\u2019\u201c\u201d\u2026\u3000-\u303f\uff01-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65]]=]
local max_lines = 16

-- Terminal table columns are separated by padding or vertical rules. Keep
-- byte positions for the cursor and display columns for alignment across CJK.
local function cells(line)
  -- Quoted filenames may contain padding or vertical rules literally. Mask
  -- closed quotes for separator lookup, preserving byte offsets into the text.
  local layout = line:gsub("(([\"'`]).-%2)", function(quoted) return string.rep("x", #quoted) end)
  local result, from = {}, 1
  while from <= #line do
    local first, last = #line + 1, #line
    for _, separator in ipairs({ "%s%s+", "\t", "|", "│", "┃", "║" }) do
      local s, e = layout:find(separator, from)
      if s and s < first then first, last = s, e end
    end
    local spaces, text = line:sub(from, first - 1):match("^(%s*)(.-)%s*$")
    if text ~= "" then
      local col = from + #spaces
      result[#result + 1] = {
        text = text,
        col = col,
        display_col = vim.fn.strdisplaywidth(line:sub(1, col - 1)),
      }
    end
    from = last + 1
  end
  return result
end

local function url_piece(text)
  local piece = text:match("^" .. url_chars)
  if not piece then return nil end
  local stop = vim.fn.match(piece, cjk_punctuation)
  if stop >= 0 then piece = piece:sub(1, stop) end
  return piece
end

local function trim_url(url)
  -- Sentence punctuation and Markdown wrappers are not part of the URL;
  -- balanced parentheses inside a path (e.g. a Wikipedia URL) are.
  url = url:gsub("[.,;:!]+$", "")
  for _, pair in ipairs({ { "(", ")" }, { "[", "]" } }) do
    local _, opens = url:gsub("%" .. pair[1], "")
    local _, closes = url:gsub("%" .. pair[2], "")
    while closes > opens and url:sub(-1) == pair[2] do
      url, closes = url:sub(1, -2), closes - 1
    end
  end
  return url
end

local function candidate(rows, row, cell, start, terminal, file)
  local opening = cell.text:sub(start - 1, start - 1)
  local quoted = file and (opening == '"' or opening == "'" or opening == "`")
  local function get_piece(text)
    if quoted then return text:match("^[^" .. opening .. "]+") end
    return url_piece(text)
  end
  local tail = cell.text:sub(start)
  local piece = get_piece(tail)
  if not piece or piece == "" then return nil end
  local fallback = {
    url = trim_url(piece),
    spans = { { row = row, first = cell.col + start - 1, last = cell.col + start + #piece - 2 } },
  }
  if opening ~= "(" and opening ~= "<" and not quoted then return fallback end

  local url, spans = "", {}
  local column = cell.display_col
  for next_row = row, row + max_lines - 1 do
    if next_row > row then
      local continuation
      for _, next_cell in ipairs(rows[next_row] or {}) do
        if next_cell.display_col == column then continuation = next_cell; break end
      end
      if not continuation or continuation.text:find("https?://") then break end
      cell, start, tail = continuation, 1, continuation.text
      piece = get_piece(tail)
      -- Use a Unicode-aware pattern: table rules are now valid token bytes too.
      if not piece or vim.fn.match(piece, [[^[-_=─━═┄┅┈┉]\+$]]) >= 0 then break end
    end
    url = url .. piece
    spans[#spans + 1] = { row = next_row, first = cell.col + start - 1, last = cell.col + start + #piece - 2 }
    local enclosed = opening == "(" and ("(" .. url):match("^%b()")
    if enclosed then return { url = enclosed:sub(2, -2), spans = spans } end
    if opening == "<" and tail:sub(#piece + 1, #piece + 1) == ">" then
      return { url = url, spans = spans }
    end
    if quoted and tail:sub(#piece + 1, #piece + 1) == opening then
      return { url = url, spans = spans }
    end
    -- Only join terminal rendering, only within this column, and only accept
    -- the result when its closing delimiter is found. Source newlines stay real.
    if not terminal or #piece ~= #tail then break end
  end
  return fallback
end

local function local_file(path)
  if path:find("://", 1, true) then return nil end
  if path:sub(1, 2) == "~/" then path = vim.uv.os_homedir() .. path:sub(2) end
  if path:sub(1, 1) ~= "/" then
    local info = vim.bo.buftype == "terminal" and vim.b.snacks_terminal
    local base = info and info.cwd or require("util.cwd").buffer_dir()
    path = vim.fs.joinpath(base, path)
  end
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file" and path or nil
end

---Open the nearest HTTP(S) URL or existing local file on this row.
---In terminals, enclosed targets may continue in the same column.
function M.open()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2] + 1
  local terminal = vim.bo.buftype == "terminal"
  local first = terminal and math.max(1, row - max_lines + 1) or row
  local last = terminal and math.min(vim.api.nvim_buf_line_count(0), row + max_lines - 1) or row
  local rows = {}
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, first - 1, last, false)) do
    rows[first + i - 1] = cells(line)
  end

  local best, best_distance = nil, math.huge
  local function consider(link, path)
    if not link then return end
    for _, span in ipairs(link.spans) do
      if span.row == row then
        local distance = math.max(span.first - col, col - span.last, 0)
        if distance < best_distance then
          best, best_distance = { target = path or link.url, file = path ~= nil }, distance
        end
      end
    end
  end
  for i = first, row do
    for _, cell in ipairs(rows[i]) do
      for start in cell.text:gmatch("()https?://") do
        consider(candidate(rows, i, cell, start, terminal))
      end
      for start, token in cell.text:gmatch("()([^%s<>\"'`%(%)%[%]]+)") do
        -- Existence distinguishes files (including extensionless names) from
        -- prose; directories such as a wrapped /tmp/ are never opened as files.
        if not token:find("://", 1, true) then
          local link = candidate(rows, i, cell, start, terminal, true)
          local path = link and local_file(link.url)
          if path then consider(link, path) end
        end
      end
    end
  end
  if best and best.file then
    -- Agent terminals protect their windows from buffer replacement. Reuse
    -- the editor in this tab, leaving the terminal and its process intact.
    if vim.bo.buftype ~= "" then
      vim.api.nvim_set_current_win(require("util.window").ensure_editor_win())
    end
    vim.cmd.edit({ args = { best.target }, magic = { file = false, bar = false } })
    return
  end
  local target = best and best.target or (vim.bo.buftype == "" and vim.fn.expand("%:p") or "")
  if target ~= "" then vim.ui.open(target) end
end

return M
