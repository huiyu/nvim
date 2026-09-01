---@module "util.debug"
---Throwaway inspection helpers for working on this configuration.
---
---Distinct from `util.logger`, which is for messages a *user* of the config
---should see. Everything here is for the person editing the Lua: `dd(value)`
---prints where it was called from, and the leak reports answer "what is holding
---all this memory / all these extmarks" during a slowdown.
---
---@example
---dd(vim.bo.filetype)              -- global, wired up in init.lua
---require("util.debug").module_leaks("snacks")
local M = {}

---Find the first stack frame outside this module, so `dd()` reports the line
---that called it rather than a line in here.
---@return string "path:line"
function M.get_loc()
  local me = debug.getinfo(1, "S")
  local level = 2
  local info = debug.getinfo(level, "S")
  while info and (info.source == me.source or info.source == "@" .. (vim.env.MYVIMRC or "") or info.what ~= "Lua") do
    level = level + 1
    info = debug.getinfo(level, "S")
  end
  info = info or me
  local source = info.source:sub(2)
  source = vim.uv.fs_realpath(source) or source
  return source .. ":" .. info.linedefined
end

---@param value any
---@param opts? { loc: string }
function M._dump(value, opts)
  opts = opts or {}
  opts.loc = opts.loc or M.get_loc()
  -- vim.notify and treesitter are both off limits in a fast event (`:h
  -- api-fast`), which is exactly where a debug print tends to be needed.
  if vim.in_fast_event() then
    return vim.schedule(function() M._dump(value, opts) end)
  end
  vim.notify(vim.inspect(value), vim.log.levels.INFO, {
    title = "Debug: " .. vim.fn.fnamemodify(opts.loc, ":~:."),
    on_open = function(win)
      vim.wo[win].conceallevel = 3
      vim.wo[win].concealcursor = ""
      vim.wo[win].spell = false
      local buf = vim.api.nvim_win_get_buf(win)
      if not pcall(vim.treesitter.start, buf, "lua") then
        vim.bo[buf].filetype = "lua"
      end
    end,
  })
end

---Pretty-print any number of values, tagged with the call site.
---Bound to the global `dd` and to `vim.print` in init.lua.
function M.dump(...)
  local args = { ... }
  ---@type any
  local value = args
  -- A single argument is dumped bare; several are dumped as the list, so
  -- `dd(a, b)` still shows both without the caller wrapping them.
  if vim.tbl_isempty(args) then
    value = nil
  elseif vim.islist(args) and #args <= 1 then
    value = args[1]
  end
  M._dump(value)
end

---Which namespace is piling up extmarks, and in which buffer.
---A plugin that never clears its marks shows up at the top.
function M.extmark_leaks()
  local counts = {}
  for name, ns in pairs(vim.api.nvim_get_namespaces()) do
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local count = #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      if count > 0 then
        counts[#counts + 1] = { name = name, buf = buf, count = count, ft = vim.bo[buf].ft }
      end
    end
  end
  table.sort(counts, function(a, b) return a.count > b.count end)
  M.dump(counts)
end

---Rough byte size of a Lua value, following tables, upvalues and metatables.
---An estimate, not a measurement: the constants are nominal and shared
---references are counted once, so use it to rank modules, not to trust totals.
---@param value any
---@param visited table<any, true>? cycle guard
---@return integer bytes
local function estimate_size(value, visited)
  if value == nil then return 0 end

  visited = visited or {}
  if visited[value] then return 0 end
  visited[value] = true

  local t = type(value)
  if t == "boolean" then
    return 4
  elseif t == "number" then
    return 8
  elseif t == "string" then
    return #value + 24
  elseif t == "function" then
    local bytes = 32
    local i = 1
    while true do
      local name, val = debug.getupvalue(value, i)
      if not name then break end
      bytes = bytes + estimate_size(val, visited)
      i = i + 1
    end
    return bytes
  elseif t == "table" then
    local bytes = 40
    for k, v in pairs(value) do
      bytes = bytes + estimate_size(k, visited) + estimate_size(v, visited)
    end
    local mt = debug.getmetatable(value)
    if mt then bytes = bytes + estimate_size(mt, visited) end
    return bytes
  end
  return 0
end

---Rank loaded modules by estimated memory, grouped by top-level name.
---@param filter string? Lua pattern; only modules matching it are counted
function M.module_leaks(filter)
  local sizes = {}
  for modname, mod in pairs(package.loaded) do
    if not filter or modname:match(filter) then
      local root = modname:match("^([^%.]+)%..*$") or modname
      sizes[root] = sizes[root] or { mod = root, mb = 0 }
      sizes[root].mb = sizes[root].mb + estimate_size(mod) / 1024 / 1024
    end
  end
  sizes = vim.tbl_values(sizes)
  table.sort(sizes, function(a, b) return a.mb > b.mb end)
  M.dump(sizes)
end

---Read a named upvalue out of a closure -- the way into a plugin's local state
---when it exposes no accessor.
---@param func function
---@param name string
---@return any
function M.get_upvalue(func, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(func, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

return M
