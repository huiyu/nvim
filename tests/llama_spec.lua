-- Inline completion: minuet (lua/plugin/lsp/minuet.lua) in front of the
-- llama-server that util.llama shares between Nvims (scripts/llama-supervise).
-- tests/fixtures/llama_fake.lua stands in for the server -- an 8 GB model is
-- not a test dependency -- and rejects any /infill body that real llama-server
-- would read differently, so everything short of the model runs here.
local t = dofile("tests/helper.lua")
local Config = require("lazy.core.config")
local llama = require("util.llama")

local fake = vim.fn.fnamemodify("tests/fixtures/llama_fake.lua", ":p")
local supervisor = vim.fn.stdpath("config") .. "/scripts/llama-supervise"
vim.env.LLAMA_SUPERVISE_INTERVAL = "1"

local function loaded(name)
  local plugin = Config.plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

local function free_port()
  local tcp = assert(vim.uv.new_tcp())
  tcp:bind("127.0.0.1", 0)
  local port = tcp:getsockname().port
  tcp:close()
  return port
end

local function fake_args(extra)
  return vim.list_extend({ "-u", "NONE", "-i", "NONE", "-l", fake }, extra or {})
end

local function answering(port)
  return vim.system({ "curl", "-sf", "-o", "/dev/null", "--max-time", "1",
    ("http://127.0.0.1:%d/health"):format(port) }):wait().code == 0
end

local function sleep(ms)
  vim.wait(ms, function() return false end)
end

-- Lines of a --mark file that start with `kind` ("start" or "infill").
local function marks(file, kind)
  if vim.fn.filereadable(file) == 0 then return {} end
  return vim.tbl_filter(function(line) return vim.startswith(line, kind) end, vim.fn.readfile(file))
end

-- util.llama with its state reset, pointed at a stand-in started with
-- `extra` flags. `share` reuses another instance's directory and port, which
-- is what a second Nvim looks like.
local function fresh_llama(extra, share)
  package.loaded["util.llama"] = nil
  local fresh = require("util.llama")
  fresh.config.dir = share and share.config.dir or vim.fn.tempname()
  fresh.config.port = share and share.config.port or free_port()
  fresh.config.server = vim.v.progpath
  fresh.config.args = fake_args(extra)
  fresh.config.recheck = 200
  return fresh
end

local notifications = {}
local notify = vim.notify
vim.notify = function(msg, level) table.insert(notifications, { msg = msg, level = level }) end

-- What minuet and util.llama report; other plugins may notify meanwhile.
local function reports(pattern)
  return vim.tbl_filter(function(n) return n.msg:find(pattern) ~= nil end, notifications)
end
local function minuet_reports() return reports("llama%.cpp") end
local function failures() return reports("^Inline completion") end

-- Loading -------------------------------------------------------------------

t.ok(not loaded("minuet-ai.nvim"), "minuet stays unloaded until the first Insert")

vim.cmd.edit("lua/util/llama.lua")
local lua_buf = vim.api.nvim_get_current_buf()
-- Neither a language server nor a Treesitter parser knows `conf`, so nothing
-- else reacts to this buffer (a parser would be downloaded on demand).
local conf_buf = vim.api.nvim_create_buf(true, false)
vim.bo[conf_buf].filetype = "conf"
local md_buf = vim.api.nvim_create_buf(true, false)
vim.bo[md_buf].filetype = "markdown"

local ensured = 0
local ensure = llama.ensure
llama.ensure = function() ensured = ensured + 1 end
vim.api.nvim_feedkeys(vim.keycode("i<Esc>"), "x", false)

t.ok(loaded("minuet-ai.nvim"), "the first Insert loads minuet")
t.eq(ensured, 0, "a headless Nvim never starts the server")
t.eq({ vim.b[lua_buf].minuet_virtual_text_auto_trigger, vim.b[conf_buf].minuet_virtual_text_auto_trigger },
  { true, true }, "buffers opened before minuet loaded still get suggestions as you type")
t.ok(not vim.b[md_buf].minuet_virtual_text_auto_trigger, "markdown does not")
local accept = vim.fn.maparg("<C-l>", "i", false, true)
t.ok((accept.desc or ""):find("minuet", 1, true) ~= nil, "<C-l> accepts the suggestion in Insert mode")

-- The same gates as seen with a UI attached. Calling the callbacks directly
-- keeps the fake UI away from every other plugin.
local minuet = require("minuet")
local predicate = minuet.config.enable_predicates[1]
local list_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function() return { { width = 80, height = 24 } } end
local function insert_enter() vim.api.nvim_exec_autocmds("InsertEnter", { group = "user_llama_ensure" }) end

vim.cmd.buffer(md_buf)
insert_enter()
local asked = predicate()
t.eq({ ensured, asked }, { 0, false }, "a buffer without suggestions does not start the server")
vim.cmd.buffer(lua_buf)
insert_enter()
t.eq(ensured, 1, "Insert in a file starts loading it")
t.eq(predicate(), false, "no request goes out before it has loaded")
t.eq(ensured, 2, "and each request first makes sure of the server")
vim.api.nvim_list_uis = list_uis
llama.ensure = ensure

-- Requests ------------------------------------------------------------------

local options = minuet.config.provider_options.openai_fim_compatible
t.eq(options.end_point, llama.url("/infill"), "requests go to the shared server's /infill")

local to_infill = options.transform[1]
local body = to_infill({ end_point = "", headers = {}, body = {
  model = "local", stream = true, prompt = "local a = 1\nlocal b = ", suffix = "\nreturn b",
} }).body
t.eq({ body.input_prefix, body.prompt, body.input_suffix, body.model, body.suffix },
  { "local a = 1\n", "local b = ", "\nreturn b", nil, nil },
  "the cursor line's head travels as `prompt`, after the FIM middle token")
body = to_infill({ end_point = "", headers = {}, body = { prompt = "local b = ", suffix = "" } }).body
t.eq({ body.input_prefix, body.prompt }, { "", "local b = " }, "on the first line there is nothing above")

local backend = require("minuet.backends.openai_fim_compatible")
local utils = require("minuet.utils")

-- Runs minuet's real request path (context, transform, curl, stream decoding,
-- item filtering) against a stand-in started with `extra` flags. `meanwhile`
-- runs right after the request goes out. Returns the items and how many
-- /infill requests the stand-in served.
local function request(extra, meanwhile)
  local port, mark = free_port(), vim.fn.tempname()
  local server = vim.system(vim.list_extend({ vim.v.progpath }, fake_args(vim.list_extend(extra,
    { "--mark", mark, "--host", "127.0.0.1", "--port", tostring(port) }))))
  t.ok(vim.wait(3000, function() return answering(port) end, 50), "the stand-in answers")
  options.end_point = ("http://127.0.0.1:%d/infill"):format(port)
  local items
  backend.complete(utils.get_context(utils.make_cmp_context()), function(result) items = result end)
  if meanwhile then meanwhile() end
  vim.wait(5000, function() return items ~= nil end, 20)
  server:kill("sigterm")
  options.end_point = llama.url("/infill")
  return items, #marks(mark, "infill")
end

vim.cmd.enew()
vim.bo.filetype = "lua"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local function add(a, b)", "  return X", "end" })
vim.api.nvim_win_set_cursor(0, { 2, 9 })

local items, served = request({ "--content", "a + b" })
t.eq({ items, served }, { { "a + b" }, 1 }, "a streamed reply becomes the suggestion")

notifications = {}
items, served = request({ "--content", "error error error", "--reply-ms", "300" }, function()
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { "  return a" })
end)
t.eq({ items, served }, { {}, 1 }, "a reply to a position the user typed past is dropped")
t.eq(minuet_reports(), {}, "dropping it reports nothing, even when the code says \"error\"")

-- Leaving Insert at column 0 moves neither the cursor nor the text.
local text_unless_stale = options.get_text_fn.stream
-- feedkeys "x!" stays in Insert until a timer leaves it, so the request is
-- sent from that timer.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local sent_from
vim.defer_fn(function()
  sent_from = vim.fn.mode()
  to_infill({ end_point = "", headers = {}, body = { prompt = "", suffix = "" } })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 50)
vim.api.nvim_feedkeys("i", "nx!", false)
t.eq({ sent_from, vim.api.nvim_win_get_cursor(0), text_unless_stale({ content = "end" }) }, { "i", { 3, 0 }, " " },
  "a reply that arrives after leaving Insert at column 0 is dropped")

-- The shared server --------------------------------------------------------

local function wait_ready(m, ms)
  return vim.wait(ms or 10000, m.ready, 50)
end

local function lock_pid(m)
  local file = io.open(m.config.dir .. "/lock/pid")
  if not file then return nil end
  local pid = tonumber(file:read("*l"))
  file:close()
  return pid
end

local function clients(m)
  return vim.fn.readdir(m.config.dir .. "/clients")
end

local function health_code(m)
  return vim.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1",
    m.url("/health") }):wait().stdout
end

llama = fresh_llama({ "--load-ms", "2500" })
llama.ensure()
t.ok(vim.wait(3000, function() return health_code(llama) == "503" end, 50), "the stand-in reports it is loading")
t.ok(not vim.wait(700, llama.ready, 20), "the server is not ready while it loads")
t.ok(wait_ready(llama), "it becomes ready once /health answers")
t.eq(clients(llama), { tostring(vim.fn.getpid()) }, "this Nvim registered itself")
local owner = lock_pid(llama)
t.ok(owner ~= nil and vim.uv.kill(owner, 0) == 0, "one supervisor holds the lock")

local second = vim.system(vim.list_extend({ supervisor, llama.config.dir, vim.v.progpath }, fake_args()))
  :wait(5000)
t.eq(second.code, 0, "a second supervisor hands over to the running one")
t.eq(lock_pid(llama), owner, "and leaves its lock alone")

local dead = vim.system({ "true" })
local dead_pid = dead.pid
dead:wait()
io.open(("%s/clients/%d"):format(llama.config.dir, dead_pid), "w"):close()
-- A live process that is not an Nvim, e.g. a reused pid after a reboot.
io.open(("%s/clients/%d"):format(llama.config.dir, owner), "w"):close()
t.ok(vim.wait(5000, function() return #clients(llama) == 1 end, 100),
  "registrations of dead or non-Nvim processes are pruned")

-- Another editor that will crash: a bare headless Nvim, registered by hand.
local other = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE",
  "--cmd", "call timer_start(60000, {-> execute('qa!')})" })
io.open(("%s/clients/%d"):format(llama.config.dir, other.pid), "w"):close()
llama.release()
sleep(2500)
t.ok(answering(llama.config.port), "the server stays while another Nvim is registered")
other:kill("sigkill")
other:wait()
t.ok(vim.wait(8000, function() return not answering(llama.config.port) end, 200),
  "it stops once the last registered Nvim is gone, crashed ones included")
t.ok(vim.wait(3000, function() return lock_pid(llama) == nil end, 100), "and the lock goes with it")

-- The last Nvim quit and a new one starts while the old supervisor is still
-- stopping: its own supervisor hands over to one that is about to exit.
notifications = {}
llama = fresh_llama()
llama.ensure()
t.ok(wait_ready(llama), "(started)")
llama.release()
t.ok(vim.wait(5000, function() return not answering(llama.config.port) end, 20), "(stopping)")
local reopened = fresh_llama(nil, llama)
reopened.ensure()
t.ok(wait_ready(reopened), "an Nvim opened while the last one's server stops gets a new one")
t.eq(failures(), {}, "without reporting a failure")

-- A crash after the server has served is not a failed start. The supervisor
-- only notices on its next round, so this Insert first hands over to it.
local crashes = vim.fn.tempname()
vim.env.LLAMA_SUPERVISE_INTERVAL = "3"
llama = fresh_llama({ "--mark", crashes })
llama.ensure()
t.ok(wait_ready(llama), "(started)")
vim.env.LLAMA_SUPERVISE_INTERVAL = "1"
local first = tonumber((marks(crashes, "start")[1] or ""):match("%d+"))
vim.uv.kill(first, "sigkill")
sleep(300)
llama.ensure()
t.ok(vim.wait(3000, function() return not llama.ready() end, 20), "(noticed)")
t.ok(wait_ready(llama), "a server that crashes after serving is brought back")
t.eq({ #marks(crashes, "start"), failures() }, { 2, {} }, "once, and without a failure report")

-- Stopping the server by hand, the way docs/DIAGNOSTICS.md says to.
vim.uv.kill(lock_pid(llama), "sigterm")
t.ok(vim.wait(8000, function() return not llama.ready() end, 50), "the Nvim that started it notices the stop")
llama.ensure()
t.ok(wait_ready(llama), "and the next Insert starts it again")
llama.release()
t.ok(vim.wait(8000, function() return not answering(llama.config.port) end, 200), "(stopped)")

-- A failed start: say so once, then stop trying for this session.
notifications = {}
local starts = vim.fn.tempname()
llama = fresh_llama({ "--fail", "--mark", starts })
llama.ensure()
t.ok(vim.wait(8000, function() return #notifications > 0 end, 50), "a server that exits on start is reported")
local message = (notifications[1] or {}).msg or ""
t.ok(message:find("exited with status", 1, true) and message:find(llama.log(), 1, true),
  "with its exit status and the log to read: " .. message)
t.ok(not llama.ready() and llama.failed(), "and is not used")
sleep(300)
llama.ensure()
sleep(1500)
t.eq(#marks(starts, "start"), 1, "the next Insert does not try again")
t.eq(#notifications, 1, "or report it again")
local log = io.open(llama.log())
t.ok(log and log:read("*a"):find("exited on its own", 1, true), "the supervisor logged why")
if log then log:close() end

-- After a reboot the lock can name a live pid that is not a supervisor.
llama = fresh_llama()
vim.fn.mkdir(llama.config.dir .. "/lock", "p")
local stale = assert(io.open(llama.config.dir .. "/lock/pid", "w"))
stale:write(tostring(vim.fn.getpid()))
stale:close()
llama.ensure()
t.ok(wait_ready(llama), "a lock held by an unrelated process is taken over")
llama.release()
t.ok(vim.wait(8000, function() return not answering(llama.config.port) end, 200),
  "releasing the only client stops the server")

vim.notify = notify
t.process_cleanup()()
t.done()
