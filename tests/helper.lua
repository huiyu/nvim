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

-- `-c qa` runs even after `luafile` raises, so an uncaught error still exits 0
-- and a failing spec would look like a passing one. `cquit` is the only exit
-- that carries a status out of a headless session.
function M.done()
  if failures > 0 then
    print(("\n%d of %d assertions failed"):format(failures, total))
    vim.cmd("cquit 1")
  end
  print(("\n%d assertions passed"):format(total))
end

return M
