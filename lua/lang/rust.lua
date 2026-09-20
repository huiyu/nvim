local function root()
  return vim.fs.root(0, "Cargo.toml") or vim.fn.getcwd()
end

-- Cargo reports the actual executables, including hashed test binaries and
-- custom target directories. Building asynchronously keeps the editor usable.
local function cargo_build(test, cwd, finish, select_artifacts)
  if vim.fn.executable("cargo") ~= 1 then
    vim.notify("Rust debugging needs cargo on PATH", vim.log.levels.WARN)
    finish()
    return
  end
  local command = { "cargo", test and "test" or "build", "--message-format=json" }
  table.insert(command, test and "--no-run" or "--bins")
  vim.notify("Building Rust " .. (test and "tests" or "binaries") .. "…")
  vim.system(command, { cwd = cwd, text = true }, vim.schedule_wrap(function(result)
    local artifacts, seen, errors = {}, {}, {}
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      local ok, item = pcall(vim.json.decode, line)
      if ok and item.reason == "compiler-message" and item.message.rendered then
        table.insert(errors, item.message.rendered)
      end
      -- JSON null is vim.NIL (truthy); dependency libraries have no executable.
      if ok and item.reason == "compiler-artifact" and type(item.executable) == "string"
        and (not test or item.profile.test) and not seen[item.executable] then
        seen[item.executable] = true
        table.insert(artifacts, { path = item.executable, source = item.target.src_path,
          label = item.target.name .. " (" .. table.concat(item.target.kind, ", ") .. ")" })
      end
    end
    if result.code ~= 0 then
      vim.notify("Cargo build failed:\n" .. table.concat(errors, "\n") .. (result.stderr or ""), vim.log.levels.ERROR)
      finish()
      return
    end
    if select_artifacts then
      select_artifacts(artifacts, finish)
    elseif #artifacts == 0 then
      vim.notify("Cargo produced no " .. (test and "test" or "binary") .. " executables", vim.log.levels.WARN)
      finish()
    elseif #artifacts == 1 then
      finish(artifacts[1].path)
    else
      vim.ui.select(artifacts, {
        prompt = "Debug Cargo target:",
        format_item = function(item) return item.label end,
      }, function(item) finish(item and item.path) end)
    end
  end))
end

local function cargo_program(test, directory)
  return function()
    local cwd = directory or root()
    return coroutine.create(function(co)
      cargo_build(test, cwd, function(path) coroutine.resume(co, path or require("dap").ABORT) end)
    end)
  end
end

local function debug_target(ctx, kind)
  local test = kind ~= "file"
  local functions = {}
  if test then
    local tree, lang = require("util.dap").syntax(ctx)
    if not tree then return end
    local query = vim.treesitter.query.parse(lang, "(function_item name: (identifier) @name) @fn")
    for _, match in query:iter_matches(tree, ctx.bufnr, 0, -1) do
      local node = match[2][1]
      local first, _, last = node:range()
      if kind == "test_file" or (first < ctx.line and last >= ctx.line - 1) then
        local parts = { vim.treesitter.get_node_text(match[1][1], ctx.bufnr) }
        local parent = node:parent()
        while parent do
          if parent:type() == "mod_item" then
            table.insert(parts, 1, vim.treesitter.get_node_text(parent:field("name")[1], ctx.bufnr))
          end
          parent = parent:parent()
        end
        table.insert(functions, table.concat(parts, "::"))
      end
    end
    if #functions == 0 then
      vim.notify("No Rust test function at this position", vim.log.levels.WARN)
      return
    end
  end
  local cwd = vim.fs.root(ctx.path, "Cargo.toml") or vim.fs.dirname(ctx.path)
  local args = {}
  local function select_artifacts(artifacts, finish)
    local function choose(choices)
      local function selected(item)
        if item then
          vim.list_extend(args, item.args or {})
          finish(item.path)
        else
          finish()
        end
      end
      if #choices == 0 then
        vim.notify("No matching Cargo target/test. Use <leader>dc for custom harnesses or module paths", vim.log.levels.WARN)
        finish()
      elseif #choices == 1 then
        selected(choices[1])
      else
        vim.ui.select(choices, { prompt = "Debug Cargo target:", format_item = function(a) return a.label end }, selected)
      end
    end
    if not test then
      local exact = vim.tbl_filter(function(a) return vim.uv.fs_realpath(a.source) == ctx.path end, artifacts)
      choose(#exact > 0 and exact or artifacts)
      return
    end
    local pending, choices = #artifacts, {}
    if pending == 0 then choose(choices); return end
    for _, artifact in ipairs(artifacts) do
      -- Conventional Rust modules: foo.rs and foo/mod.rs both contribute foo.
      -- Cargo's src_path also handles custom crate roots and integration tests.
      local source = vim.uv.fs_realpath(artifact.source) or artifact.source
      local relative = vim.fs.relpath(vim.fs.dirname(source), ctx.path)
      local prefix = source == ctx.path and "" or relative and relative:gsub("%.rs$", ""):gsub("/mod$", ""):gsub("/", "::")
      local expected = {}
      if prefix then
        for _, name in ipairs(functions) do expected[prefix == "" and name or prefix .. "::" .. name] = true end
      end
      vim.system({ artifact.path, "--list", "--format=terse" }, { cwd = cwd, text = true, timeout = 10000 },
        vim.schedule_wrap(function(result)
          local names = {}
          if result.code == 0 then
            for name in (result.stdout or ""):gmatch("([^\n]+): test") do
              if expected[name] then table.insert(names, name) end
            end
          end
          if #names > 0 then
            artifact.args = vim.list_extend({ "--exact", "--nocapture" }, names)
            table.insert(choices, artifact)
          end
          pending = pending - 1
          if pending == 0 then choose(choices) end
        end))
    end
  end
  cargo_build(test, cwd, function(path)
    if path then
      require("dap").run({ name = "rust: " .. kind, type = "codelldb", request = "launch", cwd = cwd,
        program = path, sourceLanguages = { "rust" }, args = args })
    end
  end, select_artifacts)
end

local function configuration(test)
  return setmetatable({
    name = test and "rust: cargo test" or "rust: cargo build",
    type = "codelldb", request = "launch", cwd = root,
    program = cargo_program(test), sourceLanguages = { "rust" },
    args = test and { "--nocapture" } or {},
  }, {
    -- Freeze the project before the asynchronous build. Switching buffers
    -- while Cargo runs must not change the eventual debuggee's working dir.
    __call = function(self)
      local config = vim.deepcopy(self)
      setmetatable(config, nil)
      config.cwd = root()
      config.program = cargo_program(test, config.cwd)
      return config
    end,
  })
end

return {
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "rust" } } },
  {
    "mfussenegger/nvim-dap",
    opts = {
      handlers = { codelldb = {} },
      targets = { rust = {
        file = function(ctx) debug_target(ctx, "file") end,
        test = function(ctx) debug_target(ctx, "test") end,
        test_file = function(ctx) debug_target(ctx, "test_file") end,
      } },
      configurations = {
        rust = { configuration(false), configuration(true),
          { name = "rust: attach to process", type = "codelldb", request = "attach",
            pid = function() return require("dap.utils").pick_process() end,
            sourceLanguages = { "rust" } },
        },
      },
    },
  },
}
