-- On-demand llama-server for inline completion, shared by every Nvim.
--
-- ensure() registers this process, starts scripts/llama-supervise when nothing
-- answers on the port, and polls /health until the model has loaded.
-- Completion requests wait for ready() (minuet's enable_predicates), so the
-- seconds spent loading produce no failed requests. The supervisor stops the
-- server once the last registered Nvim is gone, crashed ones included; see that
-- script for how, and for the exit codes handled in exited() below.
local M = {}

M.config = {
  -- llama-server's FIM port: its FIM presets and llama.vim use the same one.
  port = 8012,
  -- clients/<pid> registrations, the supervisor's lock and server.log.
  dir = vim.fn.stdpath("state") .. "/llama",
  server = "llama-server",
  -- Qwen2.5-Coder 7B Q8_0. On an M5 Pro a suggestion takes ~0.35 s while
  -- typing on the same line and ~0.8 s at a fresh position.
  --   --offline   start from the cached weights without contacting Hugging
  --               Face, which also never swaps in a new revision unasked.
  --   -c / -np    one 8k slot instead of the model's 32k: ~2.5 GB less memory,
  --               still several times what minuet sends.
  --   --sleep-idle-seconds
  --               after five idle minutes the weights are released (~70 MB
  --               left) and the next request reloads them in ~0.5 s.
  args = { "--fim-qwen-7b-default", "--offline", "-c", "8192", "-np", "1", "--sleep-idle-seconds", "300" },
  -- The repo --fim-qwen-7b-default loads, for :checkhealth config.
  model = "ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF",
  -- How often ensure() rechecks a server that answered, in ms. Each request
  -- calls it, so this is also how soon a server that another Nvim started,
  -- and that has since stopped, is noticed and replaced.
  recheck = 5000,
}

-- The last /health check answered.
local ready = false
-- A check, or the wait for a starting server, is in flight.
local probing = false
local registered = false
-- A server that never answered and then exited is not started again in this
-- session: every Insert would otherwise spawn another doomed one.
local start_failed = false
-- uv.now() of the last /health that answered, and of the last one asked.
local answered_at, probed_at = -1, -1

---@param path string
---@return string
function M.url(path)
  return ("http://127.0.0.1:%d%s"):format(M.config.port, path)
end

---@return string
function M.log()
  return M.config.dir .. "/server.log"
end

--- Whether the server answered /health, i.e. has finished loading.
---@return boolean
function M.ready()
  return ready
end

--- Whether a start failed in this session, which is then not retried.
---@return boolean
function M.failed()
  return start_failed
end

local function client_file()
  return ("%s/clients/%d"):format(M.config.dir, vim.fn.getpid())
end

local function register()
  if registered then return end
  vim.fn.mkdir(M.config.dir .. "/clients", "p")
  local file = io.open(client_file(), "w")
  if not file then return end
  file:close()
  registered = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("user_llama_client", { clear = true }),
    callback = M.release,
  })
end

--- Unregister this Nvim; the supervisor stops the server if it was the last.
function M.release()
  if not registered then return end
  os.remove(client_file())
  registered = false
end

---@param callback fun(ok: boolean)
local function probe(callback)
  probed_at = vim.uv.now()
  local ok = pcall(vim.system, { "curl", "-sf", "-o", "/dev/null", "--max-time", "1", M.url("/health") }, {},
    function(result)
      vim.schedule(function() callback(result.code == 0) end)
    end)
  if not ok then callback(false) end
end

local function answered()
  ready, probing, answered_at = true, false, vim.uv.now()
end

local function fail(message)
  probing = false
  if start_failed then return end
  start_failed = true
  vim.notify(("Inline completion is off: %s. See %s"):format(message, M.log()), vim.log.levels.WARN)
end

local start

---@param started_at integer uv.now() when that supervisor was started
---@param code integer its exit status
local function exited(started_at, code)
  -- 0: it handed over to the supervisor that owns the server.
  if code == 0 then return end
  ready = false
  -- 10: it stopped the server on request. A later ensure() starts a new one,
  -- and a poll in flight already retries.
  if code == 10 or not probing then return end
  if answered_at >= started_at then
    -- The server crashed after it had served, while an Insert is waiting.
    start()
  else
    fail(("llama-server exited with status %d"):format(code))
  end
end

start = function()
  local started_at = vim.uv.now()
  local cmd = { vim.fn.stdpath("config") .. "/scripts/llama-supervise", M.config.dir, vim.fn.exepath(M.config.server) }
  vim.list_extend(cmd, M.config.args)
  vim.list_extend(cmd, { "--host", "127.0.0.1", "--port", tostring(M.config.port) })
  -- Detached and without pipes: the server outlives this Nvim while others
  -- still use it, and a closed pipe would kill it with SIGPIPE.
  local ok, err = pcall(vim.system, cmd, { detach = true, stdout = false, stderr = false }, function(result)
    vim.schedule(function() exited(started_at, result.code) end)
  end)
  if not ok then fail(tostring(err)) end
  return ok
end

local function poll(deadline, retry_at)
  probe(function(ok)
    if not probing then return end
    if ok then return answered() end
    local now = vim.uv.now()
    if now > deadline then return fail("llama-server did not answer within two minutes") end
    -- The owner may be the one that is stopping because the last Nvim just
    -- quit, so it hands nothing over. Asking again is free while one runs.
    if now >= retry_at then
      start()
      retry_at = now + 2000
    end
    vim.defer_fn(function() poll(deadline, retry_at) end, 250)
  end)
end

--- Make sure the shared server is running, starting it if needed. Cheap
--- enough for every InsertEnter and every request: while the server answers,
--- or after a failed start, it checks at most every `config.recheck` ms.
function M.ensure()
  if probing or vim.fn.executable(M.config.server) == 0 then return end
  if (ready or start_failed) and vim.uv.now() - probed_at < M.config.recheck then return end
  register()
  probing = true
  probe(function(ok)
    if ok then return answered() end
    ready = false
    if start_failed then
      probing = false
    elseif start() then
      local now = vim.uv.now()
      poll(now + 120000, now + 2000)
    end
  end)
end

return M
