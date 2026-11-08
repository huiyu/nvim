-- A shell whose directory was deleted under it still starts Nvim, but the
-- process then has no working directory: `vim.uv.cwd()` is nil, and the first
-- thing to hash it -- Snacks' dashboard terminal sections, at UIEnter -- dies
-- with a traceback for what is really "your directory is gone". Recover
-- before anything else loads and say so in one line.
local M = {}

local function is_dir(path)
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

--- `path` itself if it still exists, else its nearest surviving ancestor.
---@param path string
---@return string?
local function nearest_existing(path)
  if is_dir(path) then return path end
  for dir in vim.fs.parents(path) do
    if is_dir(dir) then return dir end
  end
end

--- Local directory for file browsing/searching from the current buffer.
--- Oil supplies its directory; files supply their parent. Terminals, unnamed
--- buffers and other virtual buffers use the window/tab cwd, never their URI.
---@return string
function M.buffer_dir()
  local dir
  if vim.bo.filetype == "oil" and package.loaded.oil then
    dir = package.loaded.oil.get_current_dir()
  elseif vim.bo.buftype == "" then
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" and not name:match("^%a[%w+.-]*://") then
      dir = is_dir(name) and name or vim.fs.dirname(name)
    end
  end
  return (dir and nearest_existing(dir))
      or nearest_existing(vim.fn.getcwd())
      or vim.uv.os_homedir()
      or "/"
end

--- Try to make `dir` the working directory.
---
--- Checked through `vim.uv.cwd()` rather than chdir()'s return value: that is
--- the *previous* directory, which cannot be read when it no longer exists,
--- so a successful move from a deleted directory still reports "".
---@param dir string
---@return boolean
local function move_to(dir)
  pcall(vim.fn.chdir, dir)
  return vim.uv.cwd() ~= nil
end

--- Recover from a working directory that no longer exists.
---
--- The shell's `$PWD` still names the lost directory, so the nearest ancestor
--- that survived is the best guess at where the user wanted to be -- a pruned
--- worktree lands in its repository, a removed temp dir in its parent. Home is
--- the fallback when even that is unknown.
---@return string? report one line saying what happened; nil when the cwd was fine
function M.recover()
  if vim.uv.cwd() then return nil end

  local lost = vim.env.PWD
  local target = lost and nearest_existing(lost) or nil
  if not (target and move_to(target)) then
    target = vim.uv.os_homedir() or "/"
    move_to(target)
  end

  return ("Working directory %s no longer exists; started in %s instead"):format(
    lost and vim.fn.fnamemodify(lost, ":~") or "(unknown)",
    vim.fn.fnamemodify(target, ":~")
  )
end

--- Startup entry point, run from init.lua before options and plugins.
--- Files start at their Git root (or parent); directory arguments stay exact.
function M.setup()
  local report = M.recover()

  -- Capture an absolute argument before plugins can change the buffer or cwd.
  -- Apply only once, after startup has resolved every relative file argument.
  local first = vim.fn.argc() > 0 and vim.fn.argv(0) or nil
  if type(first) == "string" and first ~= "-" and not first:match("^%a[%w+.-]*://") then
    local path = vim.fn.fnamemodify(first, ":p")
    local initial_cwd = vim.fn.getcwd()
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("startup_cwd", { clear = true }),
      once = true,
      desc = "Set startup cwd from the first file or directory",
      callback = function()
        -- Respect an explicit :cd/:lcd/:tcd or a restored session's directory.
        if vim.fn.getcwd() ~= initial_cwd or vim.fn.haslocaldir() ~= 0 then return end
        local target = vim.uv.fs_realpath(path) or path
        if not is_dir(target) then
          target = nearest_existing(vim.fs.dirname(target))
          if target then target = vim.fs.root(target, ".git") or target end
        end
        if target then vim.cmd.cd(vim.fn.fnameescape(target)) end
      end,
    })
  end

  if not report then return end

  -- At init time vim.notify is the builtin echo, and the dashboard's first
  -- draw wipes the command line. The snacks notifier, which keeps the report
  -- on screen and in its history, is in place once lazy has set snacks up;
  -- this handler is registered before lazy's, so the notify is scheduled past
  -- the whole VeryLazy chain rather than fired inside it.
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.schedule(function() vim.notify(report, vim.log.levels.WARN) end)
    end,
  })
end

return M
