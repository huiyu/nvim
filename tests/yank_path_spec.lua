-- The <leader>y path keys: <leader>yl copies `path:line` (Visual: the selected
-- range), <leader>yg a permalink built by Snacks.gitbrowse, and the older
-- <leader>ya / <leader>yr keep working after sharing their helpers with them.
local t = dofile("tests/helper.lua")

-- A stand-in clipboard: the keys write "+, and a spec must not replace what
-- the user has on the real one.
local fake = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
vim.g.clipboard = {
  name = "yank-path-spec",
  copy = {
    ["+"] = function(lines, regtype) fake["+"] = { lines, regtype } end,
    ["*"] = function(lines, regtype) fake["*"] = { lines, regtype } end,
  },
  paste = {
    ["+"] = function() return fake["+"] end,
    ["*"] = function() return fake["*"] end,
  },
}
vim.g.loaded_clipboard_provider = nil
vim.cmd("runtime autoload/provider/clipboard.vim")
t.eq(vim.fn["provider#clipboard#Executable"](), "yank-path-spec",
  "the stand-in clipboard provider is active")

local notices = {}
local notify = vim.notify
vim.notify = function(msg, level)
  notices[#notices + 1] = { msg = msg, level = level or vim.log.levels.INFO }
end
local function clipboard() return table.concat(fake["+"][1], "\n") end
local function press(keys)
  notices = {}
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end

for lhs, mode in pairs({ ["<leader>yl"] = { "n", "x" }, ["<leader>yg"] = { "n", "x" } }) do
  for _, m in ipairs(mode) do
    t.ok(vim.fn.maparg(lhs, m, false, true).lhs ~= nil, lhs .. " is mapped in " .. m)
  end
end
t.eq(vim.fn.maparg("<leader>yl", "n", false, true).desc, "Yank path:line", "<leader>yl has its desc")
t.eq(vim.fn.maparg("<leader>yg", "n", false, true).desc, "Yank git permalink", "<leader>yg has its desc")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
-- macOS temp paths run through the /var -> /private/var symlink; buffer names
-- and the git root use the resolved one.
dir = assert(vim.uv.fs_realpath(dir))
local function git(...)
  return vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
end
git("init", "-q")
git("config", "user.email", "spec@example.com")
git("config", "user.name", "spec")
git("remote", "add", "origin", "git@github.com:example/repo.git")
vim.fn.mkdir(dir .. "/sub", "p")
vim.fn.writefile({ "one", "two", "three", "four", "five" }, dir .. "/sub/a.txt")
git("add", ".")
git("commit", "-q", "-m", "init")
local sha = vim.trim(git("rev-parse", "HEAD").stdout)

vim.cmd.edit(vim.fn.fnameescape(dir .. "/sub/a.txt"))
local function at(line) vim.api.nvim_win_set_cursor(0, { line, 0 }) end

---------------------------------------------------------------------------
-- <leader>yl
---------------------------------------------------------------------------
at(3)
press("<leader>yl")
t.eq(clipboard(), "sub/a.txt:3", "Normal <leader>yl copies the project path and the cursor line")
t.eq(vim.fn.getreg('"'), "sub/a.txt:3", "the unnamed register gets it too")
t.eq(notices[#notices].msg, "Yanked: sub/a.txt:3", "and it says what it copied")

-- The mode right after the mapping, before anything else can end Visual.
local mode_after
_G.yank_path_spec_mode = function() mode_after = vim.fn.mode() end
at(2)
press("Vj<leader>yl<Cmd>lua yank_path_spec_mode()<CR>")
t.eq(clipboard(), "sub/a.txt:2-3", "Visual <leader>yl copies the selected range")
t.eq(mode_after, "n", "the copy ends Visual mode, as y does")
at(4)
press("Vkk<leader>yl")
t.eq(clipboard(), "sub/a.txt:2-4", "a selection made upwards gives the same ascending range")
at(5)
press("v<leader>yl")
t.eq(clipboard(), "sub/a.txt:5", "a one-line selection is just that line")

---------------------------------------------------------------------------
-- <leader>yg
---------------------------------------------------------------------------
local base = "https://github.com/example/repo/blob/" .. sha .. "/sub/a.txt"
at(3)
press("<leader>yg")
t.eq(clipboard(), base .. "#L3-L3", "Normal <leader>yg copies a permalink to the cursor line")
t.eq(#notices, 1, "one notice only: Snacks' own \"Opening\" message is off")
t.eq(notices[1] and notices[1].msg, "Yanked: " .. base .. "#L3-L3", "and it reports the copy")
at(2)
press("Vjj<leader>yg<Cmd>lua yank_path_spec_mode()<CR>")
t.eq(clipboard(), base .. "#L2-L4", "Visual <leader>yg links the selected lines")
t.eq(mode_after, "n", "and leaves Visual mode")

-- A later commit elsewhere in the repository does not move the link: it names
-- the last commit that touched this file.
vim.fn.writefile({ "other" }, dir .. "/b.txt")
git("add", "b.txt")
git("commit", "-q", "-m", "unrelated")
at(1)
press("<leader>yg")
t.eq(clipboard(), base .. "#L1-L1", "the permalink stays on the file's own last commit")

---------------------------------------------------------------------------
-- The older path keys, and a buffer with no file
---------------------------------------------------------------------------
press("<leader>ya")
t.eq(clipboard(), dir .. "/sub/a.txt", "<leader>ya still copies the absolute path")
press("<leader>yr")
t.eq(clipboard(), "sub/a.txt", "<leader>yr still copies the project path")

vim.cmd.enew()
fake["+"] = { { "untouched" }, "v" }
for _, keys in ipairs({ "<leader>yl", "<leader>yg", "V<leader>yl", "V<leader>yg" }) do
  press(keys)
  t.eq(clipboard(), "untouched", keys .. " in a buffer with no file leaves the clipboard alone")
  local last = notices[#notices]
  t.ok(last and last.msg == "Buffer has no file" and last.level == vim.log.levels.WARN,
    keys .. " warns that there is no file")
end

vim.notify = notify
_G.yank_path_spec_mode = nil
vim.fn.delete(dir, "rf")
t.done()
