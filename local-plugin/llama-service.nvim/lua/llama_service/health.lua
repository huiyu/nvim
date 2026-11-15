local M = {}
local health = vim.health
function M.check()
  local llama = require("llama_service")
  health.start("config: inline completion")
  if vim.fn.executable(llama.config.server) ~= 1 then
    health.warn("llama-server not found — no AI ghost text", { "brew install llama.cpp" })
  else
    health.ok("llama-server found — started on the first Insert, shared by every Nvim")
    -- --offline means a missing model is a failed start, not a download.
    -- Resolved the way llama.cpp does, where an empty variable counts as unset.
    local function env(name)
      local value = vim.env[name]
      return value ~= "" and value or nil
    end
    local cache = env("HF_HUB_CACHE") or env("HUGGINGFACE_HUB_CACHE") or ((env("HF_HOME")
      or (env("XDG_CACHE_HOME") or (vim.uv.os_homedir() .. "/.cache")) .. "/huggingface") .. "/hub")
    local snapshots = ("%s/models--%s/snapshots"):format(cache, (llama.config.model:gsub("/", "--")))
    if #vim.fn.glob(snapshots .. "/*/*.gguf", false, true) > 0 then
      health.ok(("%s is in %s"):format(llama.config.model, cache))
    else
      health.warn(("%s is not in %s; the server starts --offline and cannot fetch it"):format(llama.config.model, cache),
        { "Download it once (~8 GB): llama-server --fim-qwen-7b-default, then Ctrl-C once it is listening" })
    end
    local answer = vim.fn.executable("curl") == 1
      and vim.system({ "curl", "-sf", "-o", "/dev/null", "--max-time", "1", llama.url("/health") }):wait()
    if answer and answer.code == 0 then
      health.ok("server answering at " .. llama.url(""))
    elseif llama.failed() then
      health.warn(("the server failed to start in this Nvim and is not retried; see %s"):format(llama.log()),
        { "Fix what the log reports, then restart Nvim" })
    else
      health.info(("server not running (it starts on the next Insert); last log: %s"):format(llama.log()))
    end
  end

end
return M
