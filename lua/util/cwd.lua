-- Working-directory resolution. Requiring this module changes nothing: the
-- startup wiring (recover, then pick the startup cwd at VimEnter) lives in
-- lua/config/cwd.lua, the first step of lua/config/init.lua.
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
--- A shell whose directory was deleted under it still starts Nvim, but the
--- process then has no working directory: `vim.uv.cwd()` is nil, and the first
--- thing to hash it -- Snacks' dashboard terminal sections, at UIEnter -- dies
--- with a traceback for what is really "your directory is gone".
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

--- The directory Nvim starts in for a file or directory argument.
---
--- A directory is used exactly. A file uses its nearest `.git` ancestor (a
--- `.git` file counts, so worktrees and submodules keep their own root), else
--- its parent. Symlinks resolve to their target first, and a parent that does
--- not exist yet falls back to its nearest existing ancestor.
---@param path string an absolute path
---@return string?
function M.startup_dir(path)
  local target = vim.uv.fs_realpath(path) or path
  if is_dir(target) then return target end
  local dir = nearest_existing(vim.fs.dirname(target))
  return dir and (vim.fs.root(dir, ".git") or dir)
end

return M
