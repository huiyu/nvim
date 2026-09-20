-- Minimal assertion helper for headless config tests.
--
-- Loaded with `dofile`, not `require`: Nvim's `require` only searches
-- `runtimepath/lua/`, and `tests/` deliberately stays out of the runtime path so
-- test code can never be pulled into a real editing session.
--
-- Specs run as `nvim --headless -u init.lua -c 'luafile tests/<x>_spec.lua' -c qa`
-- from the repository root, so the relative path below resolves.

local M = {}

local failures = 0
local total = 0

function M.ok(cond, what)
  total = total + 1
  if cond then
    print("ok - " .. what)
  else
    failures = failures + 1
    print("FAIL - " .. what)
  end
end

-- Only widen the message on failure; a passing run stays one line per assertion.
function M.eq(got, want, what)
  if vim.deep_equal(got, want) then
    M.ok(true, what)
  else
    M.ok(false, ("%s\n       got:  %s\n       want: %s")
      :format(what, vim.inspect(got), vim.inspect(want)))
  end
end

-- Snapshot before closing a native debugger: it can leave debugserver in its
-- own process group. Only descendants of this spec's Nvim are eligible.
function M.process_cleanup()
  if vim.fn.has("unix") == 0 then return function() end end
  local result = vim.system({ "ps", "-axo", "pid=,ppid=" }, { text = true }):wait()
  local children = {}
  for pid, parent in (result.stdout or ""):gmatch("(%d+)%s+(%d+)") do
    parent, pid = tonumber(parent), tonumber(pid)
    children[parent] = children[parent] or {}
    table.insert(children[parent], pid)
  end
  local owned = {}
  local function collect(parent)
    for _, pid in ipairs(children[parent] or {}) do collect(pid); table.insert(owned, pid) end
  end
  collect(vim.fn.getpid())
  return function()
    for _, pid in ipairs(owned) do vim.uv.kill(pid, "sigterm") end
    vim.wait(1000, function()
      for _, pid in ipairs(owned) do if vim.uv.kill(pid, 0) == 0 then return false end end
      return true
    end, 50)
    for _, pid in ipairs(owned) do
      if vim.uv.kill(pid, 0) == 0 then vim.uv.kill(pid, "sigkill") end
    end
  end
end

-- Always exit through `cquit`, never by falling through to `-c qa`.
--
-- Two reasons. `cquit` is the only exit that carries a status out of a headless
-- session, so a failing spec can be told from a passing one. And it quits
-- unconditionally: specs leave modified scratch buffers behind, which make `:qa`
-- raise E37 and then block forever waiting for a confirmation nobody can give.
function M.done()
  if failures > 0 then
    print(("\n%d of %d assertions failed"):format(failures, total))
    vim.cmd("cquit 1")
  end
  print(("\n%d assertions passed"):format(total))
  vim.cmd("cquit 0")
end

return M
