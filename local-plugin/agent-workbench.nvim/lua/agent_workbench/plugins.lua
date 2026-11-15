-- Local plugins for the native terminals. CodeCompanion owns no part of this
-- loader: each CLI discovers the plugin's skills, MCP servers and hooks itself.
local M = {}

local function fail(message)
  error("AI plugins: " .. message, 0)
end

local manifests = {
  claude = { ".claude-plugin/plugin.json" },
  codex = { "plugin.json", ".codex-plugin/plugin.json", ".claude-plugin/plugin.json" },
}

local function manifest(dir, host)
  for _, relative in ipairs(manifests[host]) do
    local file = dir .. "/" .. relative
    if vim.fn.filereadable(file) == 1 then
      local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), "\n"))
      if not ok or type(value) ~= "table" or type(value.name) ~= "string"
        or not value.name:match("^[%w][%w_-]*$") then
        fail("invalid plugin name or JSON in " .. file)
      end
      return { name = value.name, path = dir }
    end
  end
end

---Each entry is a plugin directory, or a distribution root with host/<plugin>
---children (e.g. GPK's dist/marketplace). Resolve only the requested host.
---@param host "claude"|"codex"
---@return { name: string, path: string }[]
function M.resolve(host)
  assert(manifests[host], "unknown plugin host: " .. tostring(host))
  local plugins, paths, names = {}, {}, {}
  local function add(plugin)
    local real = vim.uv.fs_realpath(plugin.path) or plugin.path
    if paths[real] then return end
    if names[plugin.name] then fail("duplicate " .. host .. " plugin name: " .. plugin.name) end
    paths[real], names[plugin.name] = true, true
    plugins[#plugins + 1] = plugin
  end
  for _, configured in ipairs(vim.split(vim.env.NVIM_AI_PLUGIN_DIR or "", ",", { trimempty = true })) do
    local trimmed = vim.trim(configured)
    if trimmed ~= "" then
      local root = vim.fs.abspath(vim.fs.normalize(trimmed))
      if vim.fn.isdirectory(root) ~= 1 then fail("directory not found: " .. root) end
      local direct = manifest(root, host)
      if direct then
        add(direct)
      else
        local host_root = root .. "/" .. host
        local single = manifest(host_root, host)
        if single then
          add(single)
        elseif vim.fn.isdirectory(host_root) == 1 then
          local children = vim.fn.readdir(host_root)
          table.sort(children)
          local found = false
          for _, child in ipairs(children) do
            local plugin = manifest(host_root .. "/" .. child, host)
            if plugin then add(plugin); found = true end
          end
          if not found then fail("no " .. host .. " plugins in " .. host_root) end
        else
          fail("no " .. host .. " plugin manifest or host directory in " .. root)
        end
      end
    end
  end
  return plugins
end

---Arguments only; shell escaping belongs to the Claude terminal's string builder.
function M.claude_args()
  local args = {}
  for _, plugin in ipairs(M.resolve("claude")) do
    vim.list_extend(args, { "--plugin-dir", plugin.path })
  end
  return args
end

-- JSON strings have the same escapes as TOML basic strings for filesystem paths.
-- Quote DEL too, which TOML forbids literally (JSON permits it).
local function toml_string(value)
  return vim.json.encode(value):gsub(string.char(127), "\\u007F")
end

-- Reuse an enclosing native catalog when it already names this exact package.
-- In particular GPK must retain gpk@gpk, rather than load a second copy beside
-- a globally installed version. A source override fixes its path for this run.
local function existing_marketplace(plugin)
  local root = plugin.path
  for _ = 1, 3 do
    local file = root .. "/.agents/plugins/marketplace.json"
    if vim.fn.filereadable(file) == 1 then
      local ok, catalog = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), "\n"))
      if ok and type(catalog) == "table" and type(catalog.name) == "string"
        and catalog.name:match("^[%w][%w_-]*$") and type(catalog.plugins) == "table" then
        for _, entry in ipairs(catalog.plugins) do
          local source = entry.source
          local relative = type(source) == "string" and source
            or (type(source) == "table" and source.source == "local" and source.path)
          if entry.name == plugin.name and type(relative) == "string"
            and vim.uv.fs_realpath(root .. "/" .. relative) == vim.uv.fs_realpath(plugin.path) then
            return { name = catalog.name, root = root, plugins = {} }
          end
        end
      end
    end
    root = vim.fs.dirname(root)
  end
end

---Codex has no --plugin-dir. Give it a Neovim-owned local marketplace and
---per-invocation enables, installing fresh local snapshots before each spawn.
---Installation's config writes go to a disposable CODEX_HOME; only plugins/
---is shared with the real home. Login, config.toml and hook trust stay native.
---@return string[]
function M.codex_args()
  local plugins = M.resolve("codex")
  if #plugins == 0 then return {} end
  local identity = {}
  for _, plugin in ipairs(plugins) do identity[#identity + 1] = { plugin.name, plugin.path } end
  local name = "nvim-local-" .. vim.fn.sha256(vim.json.encode(identity)):sub(1, 12)
  local generated = { name = name, root = vim.fn.stdpath("cache") .. "/ai-plugins/" .. name, plugins = {}, generated = true }
  local groups, by_name = {}, {}
  for _, plugin in ipairs(plugins) do
    local group = existing_marketplace(plugin) or generated
    local previous = by_name[group.name]
    if previous then
      if previous.root ~= group.root then fail("duplicate Codex marketplace name: " .. group.name) end
      group = previous
    else
      groups[#groups + 1], by_name[group.name] = group, group
    end
    group.plugins[#group.plugins + 1] = plugin
  end
  local args, selectors = {}, {}
  for _, group in ipairs(groups) do
    local root, catalog = group.root, {}
    vim.list_extend(args, { "-c", "marketplaces." .. group.name .. "={source_type=\"local\",source=" .. toml_string(root) .. "}" })
    if group.generated then
      vim.fn.mkdir(root .. "/.agents/plugins", "p")
      vim.fn.mkdir(root .. "/plugins", "p")
    end
    for _, plugin in ipairs(group.plugins) do
      if group.generated then
        local link = root .. "/plugins/" .. plugin.name
        local existing = vim.uv.fs_lstat(link)
        if not existing then
          local ok, err = vim.uv.fs_symlink(plugin.path, link, { dir = true })
          if not ok and vim.uv.fs_realpath(link) ~= vim.uv.fs_realpath(plugin.path) then
            fail("cannot link " .. plugin.path .. ": " .. tostring(err))
          end
        elseif existing.type ~= "link" or vim.uv.fs_realpath(link) ~= vim.uv.fs_realpath(plugin.path) then
          fail("unexpected file at " .. link)
        end
        catalog[#catalog + 1] = {
          name = plugin.name, source = { source = "local", path = "./plugins/" .. plugin.name },
          policy = { installation = "AVAILABLE", authentication = "ON_INSTALL" }, category = "Productivity",
        }
      end
      local selector = plugin.name .. "@" .. group.name
      selectors[#selectors + 1] = selector
      -- Override paths are split on dots by Codex, not parsed as TOML keys: a
      -- literal quoted key here would silently fail to enable the plugin.
      vim.list_extend(args, { "-c", "plugins." .. selector .. ".enabled=true" })
    end
    if group.generated then
      local catalog_file = root .. "/.agents/plugins/marketplace.json"
      local temporary = catalog_file .. "." .. vim.fn.getpid()
      vim.fn.writefile({ vim.json.encode({ name = group.name, plugins = catalog }) }, temporary)
      local renamed, rename_error = vim.uv.fs_rename(temporary, catalog_file)
      if not renamed then fail("cannot write marketplace: " .. tostring(rename_error)) end
    end
  end

  local codex_home = vim.fs.abspath(vim.fs.normalize(vim.env.CODEX_HOME or "~/.codex"))
  vim.fn.mkdir(codex_home .. "/plugins", "p")
  local installer = vim.fn.tempname()
  vim.fn.mkdir(installer, "p")
  local ok, err = pcall(function()
    local linked, link_error = vim.uv.fs_symlink(codex_home .. "/plugins", installer .. "/plugins", { dir = true })
    if not linked then fail("cannot share Codex's plugin cache: " .. tostring(link_error)) end
    for _, selector in ipairs(selectors) do
      local command = vim.list_extend({ "codex" }, args)
      vim.list_extend(command, { "plugin", "add", selector, "--json" })
      local result = vim.system(command, {
        cwd = installer, env = { CODEX_HOME = installer }, text = true, timeout = 15000,
      }):wait()
      if result.code ~= 0 then
        fail("Codex could not load " .. selector .. ": " .. vim.trim(result.stderr or "")
          .. " (requires Codex with local plugin marketplace support)")
      end
    end
  end)
  -- delete() removes the symlink itself, never the shared plugin cache.
  vim.fn.delete(installer, "rf")
  if not ok then error(err, 0) end
  return args
end

return M
