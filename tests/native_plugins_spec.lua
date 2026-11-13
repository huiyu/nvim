-- Native local plugins: host selection, real offline Codex discovery, isolated
-- config writes and refresh of local edits. The launch argv through both
-- Codex wrappers is tests/agent_hook_spec.lua's. No conversation, model
-- request, MCP server or plugin hook is started.
local t = dofile("tests/helper.lua")
local plugins = require("ai.plugins")
local root = vim.fn.tempname() .. " plug in 'quoted'"
vim.fn.mkdir(root, "p")
local saved = { dirs = vim.env.NVIM_AI_PLUGIN_DIR, home = vim.env.CODEX_HOME, path = vim.env.PATH }
local function write(file, value)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  local content = type(value) == "table" and vim.json.encode(value) or value
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), file)
end
local function fixture(dir, host, name)
  write(dir .. "/." .. host .. "-plugin/plugin.json", {
    name = name, version = "1.0.0", description = "Offline native plugin fixture", skills = "./skills/",
    hooks = "./hooks/hooks.json", mcpServers = "./.mcp.json",
  })
  write(dir .. "/skills/hello/SKILL.md", "---\nname: hello\ndescription: Offline skill discovery\n---\nFirst revision.")
  write(dir .. "/hooks/hooks.json", { hooks = { UserPromptSubmit = {
    { hooks = { { type = "command", command = "true", timeout = 5 } } },
  } } })
  write(dir .. "/.mcp.json", { mcpServers = { fixture = { command = "false", args = {} } } })
end
local bundle, compat = root .. "/bundle", root .. "/compatible"
fixture(bundle .. "/claude/demo", "claude", "demo")
fixture(bundle .. "/codex/demo", "codex", "demo")
fixture(compat, "claude", "compatible")

vim.env.NVIM_AI_PLUGIN_DIR = ""
t.eq(plugins.claude_args(), {}, "unset/empty plugin dirs leave Claude unchanged")
t.eq(plugins.codex_args(), {}, "empty plugin dirs need no Codex installation")
vim.env.NVIM_AI_PLUGIN_DIR = " , " .. bundle .. ",," .. compat .. "," .. compat .. "/, "
t.eq(plugins.resolve("claude"), {
  { name = "demo", path = bundle .. "/claude/demo" }, { name = "compatible", path = compat },
}, "Claude selects its own distribution package and deduplicates a repeated directory")
t.eq(plugins.resolve("codex"), {
  { name = "demo", path = bundle .. "/codex/demo" }, { name = "compatible", path = compat },
}, "Codex selects its own package and accepts a Claude-compatible plugin")
t.eq(plugins.claude_args(), { "--plugin-dir", bundle .. "/claude/demo", "--plugin-dir", compat },
  "Claude receives repeated plugin flags without premature shell escaping")
local dirs = vim.env.NVIM_AI_PLUGIN_DIR
vim.env.NVIM_AI_PLUGIN_DIR = root .. "/missing"
local ok, err = pcall(plugins.resolve, "codex")
t.ok(not ok and tostring(err):find("directory not found", 1, true), "missing plugin paths fail explicitly")
fixture(root .. "/duplicate", "claude", "compatible")
vim.env.NVIM_AI_PLUGIN_DIR = compat .. "," .. root .. "/duplicate"
ok, err = pcall(plugins.resolve, "codex")
t.ok(not ok and tostring(err):find("duplicate codex plugin name", 1, true), "a name collision cannot silently replace another plugin")
vim.env.NVIM_AI_PLUGIN_DIR = dirs

if vim.fn.executable("codex") == 1 then
  local home = root .. "/codex-home"
  local original = '# Must survive plugin installation byte-for-byte.\nmodel_reasoning_effort = "medium"'
  write(home .. "/config.toml", original)
  write(home .. "/keep.txt", "untouched")
  vim.env.CODEX_HOME = home
  local args = plugins.codex_args()
  t.eq(table.concat(vim.fn.readfile(home .. "/config.toml"), "\n"), original,
    "local installation never rewrites the user's Codex config")
  t.eq(vim.fn.readfile(home .. "/keep.txt"), { "untouched" }, "the temporary home's cleanup does not follow its plugin-cache symlink")
  local market = args[2]:match("^marketplaces%.([^=]+)=")
  t.ok(market ~= nil and args[4] == "plugins.demo@" .. market .. ".enabled=true",
    "Codex gets an invocation-local marketplace and an unquoted override key")

  -- Inspect native discovery, without starting a thread (which would start the
  -- MCP fixture). Filtering on pluginId distinguishes bundled system skills.
  local function discover(overrides)
    local responses, pending = {}, ""
    local command = vim.list_extend({ "codex" }, overrides or args)
    command[#command + 1] = "app-server"
    local env = vim.fn.environ()
    env.OPENAI_API_KEY, env.CODEX_API_KEY = nil, nil
    local proc = vim.system(command, {
      cwd = root, env = env, clear_env = true, stdin = true, text = true,
      stdout = function(_, chunk)
        if not chunk then return end
        pending = pending .. chunk
        while pending:find("\n", 1, true) do
          local line, rest = pending:match("^(.-)\n(.*)$")
          pending = rest
          local decoded, msg = pcall(vim.json.decode, line)
          if decoded and msg.id then responses[msg.id] = msg end
        end
      end,
    })
    local function request(id, method, params)
      proc:write(vim.json.encode({ id = id, method = method, params = params }) .. "\n")
      vim.wait(10000, function() return responses[id] ~= nil end, 20)
      return responses[id] or {}
    end
    request(1, "initialize", { clientInfo = { name = "nvim-plugin-spec", version = "0.0.0" }, capabilities = { experimentalApi = true } })
    proc:write('{"method":"initialized"}\n')
    local skills = request(2, "skills/list", { cwds = { root }, forceReload = true })
    local catalog = vim.fn.stdpath("cache") .. "/ai-plugins/" .. market .. "/.agents/plugins/marketplace.json"
    local demo = request(3, "plugin/read", { marketplacePath = catalog, pluginName = "demo" })
    local legacy = request(4, "plugin/read", { marketplacePath = catalog, pluginName = "compatible" })
    proc:kill(15)
    proc:wait(2000)
    return skills, demo, legacy
  end
  local skills, demo, legacy = discover()
  local found = {}
  for _, item in ipairs(skills.result and skills.result.data or {}) do
    for _, skill in ipairs(item.skills or {}) do
      if type(skill.pluginId) == "string" then found[skill.name] = skill.path end
    end
  end
  t.ok(found["demo:hello"] and found["compatible:hello"], "Codex actually discovers native and Claude-compatible packaged skills")
  for name, result in pairs({ native = demo, compatible = legacy }) do
    local plugin = result.result and result.result.plugin
    t.ok(plugin and plugin.summary.enabled and #plugin.hooks > 0 and #plugin.mcpServers > 0,
      name .. " plugin: enabled with native hooks and MCP definitions (neither executed)")
  end
  local normal = discover({})
  local globally_enabled = {}
  for _, item in ipairs(normal.result and normal.result.data or {}) do
    for _, skill in ipairs(item.skills or {}) do
      if type(skill.pluginId) == "string" and skill.pluginId:find("@" .. market, 1, true) then
        globally_enabled[#globally_enabled + 1] = skill.name
      end
    end
  end
  t.eq(globally_enabled, {}, "installed local plugins are not enabled in a normal Codex invocation")
  write(bundle .. "/codex/demo/skills/hello/SKILL.md", "---\nname: hello\ndescription: Offline skill discovery\n---\nSecond revision.")
  t.eq(plugins.codex_args(), args, "the marketplace identity stays stable when plugin content changes")
  t.ok(found["demo:hello"] and table.concat(vim.fn.readfile(found["demo:hello"]), "\n"):find("Second revision.", 1, true),
    "a new launch refreshes local edits even without a version bump")

  -- A distribution such as GPK already has a native catalog. Reuse its ID so
  -- a globally installed copy is refreshed, not loaded a second time. Even a
  -- stale configured source is overridden only for this invocation.
  write(bundle .. "/.agents/plugins/marketplace.json", {
    name = "existing", plugins = { { name = "demo", source = { source = "local", path = "./codex/demo" },
      policy = { installation = "AVAILABLE", authentication = "ON_INSTALL" }, category = "Productivity" } },
  })
  local configured = original .. '\n[marketplaces.existing]\nsource_type = "local"\nsource = "'
    .. root .. '/missing-old-source"\n[plugins."demo@existing"]\nenabled = true'
  write(home .. "/config.toml", configured)
  args = plugins.codex_args()
  t.ok(args[2]:find("marketplaces.existing=", 1, true) == 1 and args[4] == "plugins.demo@existing.enabled=true",
    "a native catalog retains the existing plugin identity and overrides its stale source")
  local reused = discover()
  local identities = {}
  for _, item in ipairs(reused.result and reused.result.data or {}) do
    for _, skill in ipairs(item.skills or {}) do
      if skill.name == "demo:hello" then identities[#identities + 1] = skill.pluginId end
    end
  end
  t.eq(identities, { "demo@existing" }, "only one copy is loaded beside the existing global plugin settings")
  t.eq(table.concat(vim.fn.readfile(home .. "/config.toml"), "\n"), configured,
    "the configured global marketplace source and enablement remain byte-for-byte unchanged")

  -- Only this test's generated marketplace is removed; never the real cache.
  vim.fn.delete(vim.fn.stdpath("cache") .. "/ai-plugins/" .. market, "rf")
else
  t.ok(true, "Codex is not installed; native discovery checks skipped")
end

vim.env.NVIM_AI_PLUGIN_DIR, vim.env.CODEX_HOME, vim.env.PATH = saved.dirs, saved.home, saved.path
vim.fn.delete(root, "rf")
t.done()
