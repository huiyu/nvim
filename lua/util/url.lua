local M = {}

-- Include UTF-8 bytes so removing the <cfile> shortcut does not truncate URLs
-- with Unicode hostnames, paths, or query values.
local url_chars = "[%w%-%._~:/?#%[%]@!$&'()*+,;%%=\128-\255]+"
local max_lines = 16

-- Terminal table columns are separated by padding or vertical rules. Keep
-- byte positions for the cursor and display columns for alignment across CJK.
local function cells(line)
  local result, from = {}, 1
  while from <= #line do
    local first, last = #line + 1, #line
    for _, separator in ipairs({ "%s%s+", "\t", "|", "│", "┃", "║" }) do
      local s, e = line:find(separator, from)
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

local function candidate(rows, row, cell, start, terminal)
  local opening = cell.text:sub(start - 1, start - 1)
  local tail = cell.text:sub(start)
  local piece = tail:match("^" .. url_chars)
  local fallback = {
    url = trim_url(piece),
    spans = { { row = row, first = cell.col + start - 1, last = cell.col + start + #piece - 2 } },
  }
  if opening ~= "(" and opening ~= "<" then return fallback end

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
      piece = tail:match("^" .. url_chars)
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
    -- Only join terminal rendering, only within this column, and only accept
    -- the result when its closing delimiter is found. Source newlines stay real.
    if not terminal or #piece ~= #tail then break end
  end
  return fallback
end

---Open the nearest HTTP(S) URL on this row, or the current file if none exists.
---In terminals, a parenthesized/autolink URL may continue in the same column.
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

  local best_url, best_distance = nil, math.huge
  for i = first, row do
    for _, cell in ipairs(rows[i]) do
      for start in cell.text:gmatch("()https?://") do
        local link = candidate(rows, i, cell, start, terminal)
        for _, span in ipairs(link.spans) do
          if span.row == row then
            local distance = math.max(span.first - col, col - span.last, 0)
            if distance < best_distance then best_url, best_distance = link.url, distance end
          end
        end
      end
    end
  end
  local target = best_url or vim.fn.expand("%:p")
  if target ~= "" then vim.ui.open(target) end
end

return M
