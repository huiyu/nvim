-- Exercise real VimEnter startup: -c qa would quit before the cwd hook runs.
local t = dofile("tests/helper.lua")
local config = vim.fn.fnamemodify("init.lua", ":p")
local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
base = vim.uv.fs_realpath(base)
local repo, loose, worktree = base .. "/project with spaces", base .. "/loose", base .. "/worktree"
for _, dir in ipairs({ repo .. "/.git", repo .. "/src", loose, worktree .. "/src" }) do
  vim.fn.mkdir(dir, "p")
end
local file, other = repo .. "/src/one.txt", worktree .. "/src/two.txt"
vim.fn.writefile({ "one" }, file)
vim.fn.writefile({ "two" }, other)
-- Worktrees and submodules use a .git file rather than a directory.
vim.fn.writefile({ "gitdir: ../common/.git/worktrees/example" }, worktree .. "/.git")
vim.fn.writefile({ "loose" }, loose .. "/plain.txt")

local probe = base .. "/probe.lua"
vim.fn.writefile(vim.split([[
local result = {
  cwd = vim.fn.getcwd(), file = vim.api.nvim_buf_get_name(0),
  agent_root = require("ai.config").project_root(),
  oil_dir = package.loaded.oil and package.loaded.oil.get_current_dir(),
}
if vim.env.CWD_NEXT == "1" then
  vim.cmd("next")
  result.next_file = vim.api.nvim_buf_get_name(0)
end
if vim.env.CWD_EDIT ~= "" then
  vim.cmd.edit(vim.fn.fnameescape(vim.env.CWD_EDIT))
end
result.later_cwd = vim.fn.getcwd()
io.stdout:write(vim.json.encode(result) .. "\n")
vim.cmd("cquit 0")
]], "\n", { plain = true }), probe)

local function child(args, opts)
  opts = opts or {}
  local command = { vim.v.progpath, "--headless", "-u", config, "-i", "NONE" }
  vim.list_extend(command, args)
  vim.list_extend(command, { "-c", [[lua vim.api.nvim_create_autocmd("VimEnter", {
    once = true, callback = function()
      vim.schedule(function()
        local ok, err = pcall(dofile, vim.env.CWD_PROBE)
        if not ok then io.stderr:write(tostring(err)); vim.cmd("cquit 1") end
      end)
    end,
  })]] })
  local result = vim.system(command, {
    cwd = base, text = true, stdin = opts.stdin,
    env = {
      NVIM_AI_PROVIDER = opts.provider or require("ai.config").default,
      CWD_PROBE = probe, CWD_EDIT = opts.edit or "", CWD_NEXT = opts.next and "1" or "",
    },
  }):wait(20000)
  local ok, decoded = pcall(vim.json.decode, result.stdout or "")
  t.ok(result.code == 0 and ok, "startup probe exits cleanly"
    .. (result.code == 0 and ok and "" or ": " .. (result.stderr or "")))
  return ok and decoded or {}
end

for _, provider in ipairs({ "claude", "codex" }) do
  local result = child({ file }, { provider = provider, edit = other })
  t.eq(result.cwd, repo, provider .. ": a file starts in its Git root")
  t.eq(result.agent_root, repo, provider .. ": the agent uses the same project")
  t.eq(result.later_cwd, repo, provider .. ": editing another repository leaves cwd alone")
end

t.eq(child({ "project with spaces/src/one.txt" }).cwd, repo, "relative paths resolve before cwd changes")
t.eq(child({ repo .. "/src/new/deeper/file.txt" }).cwd, repo, "a new file with missing parents finds its repository")
t.eq(child({ other }).cwd, worktree, "a .git file identifies a worktree or submodule root")
t.eq(child({ loose .. "/plain.txt" }).cwd, loose, "a non-Git file uses its parent directory")
t.eq(child({ loose .. "/missing/new.txt" }).cwd, loose, "a missing non-Git parent uses its nearest existing ancestor")
t.eq(child({ repo .. "/src" }).cwd, repo .. "/src", "a directory argument stays at that exact directory")
local directory = child({ "project with spaces/src" })
t.eq(directory.cwd, repo .. "/src", "a relative directory argument sets cwd correctly")
t.eq(directory.oil_dir, repo .. "/src/", "Oil opens the original directory after cwd changes")
t.eq(child({}).cwd, base, "startup without arguments keeps the shell directory")
t.eq(child({ "-" }, { stdin = "text\n" }).cwd, base, "stdin keeps the shell directory")

local nested = repo .. "/vendor/inner"
vim.fn.mkdir(nested .. "/.git", "p")
vim.fn.writefile({ "nested" }, nested .. "/nested.txt")
t.eq(child({ nested .. "/nested.txt" }).cwd, nested, "the nearest nested repository wins")
assert(vim.uv.fs_symlink(file, base .. "/link.txt"))
t.eq(child({ base .. "/link.txt" }).cwd, repo, "a symlinked file uses the target repository")

for _, scope in ipairs({ "cd", "lcd", "tcd" }) do
  t.eq(child({ file, "-c", scope .. " " .. vim.fn.fnameescape(loose) }).cwd, loose,
    "an explicit startup :" .. scope .. " takes precedence")
end

local multiple = child({ "project with spaces/src/one.txt", "worktree/src/two.txt" }, { next = true })
t.eq(multiple.cwd, repo, "the first file determines cwd with multiple arguments")
t.eq(multiple.next_file, other, "changing cwd preserves subsequent relative arguments")
t.eq(multiple.later_cwd, repo, ":next does not change cwd again")

vim.fn.delete(base, "rf")
t.done()
