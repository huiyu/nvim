-- TypeScript / JavaScript *language* support.
--
-- This file owns the language itself and is runtime-agnostic: the same setup
-- applies whether the code targets Node, the browser, Deno or Bun. Web-frontend
-- tooling (HTML / CSS / Tailwind) lives in `lang/frontend.lua`, not here.
-- ,x runners (dispatched centrally by util.run; keymap in mappings.lua).
-- TS has no dependency-free single-file runner, so use `npx tsx` (resolves a
-- project/global tsx; the terminal shows a clear error if tsx is unavailable).
require("util.run").register("javascript", function(path)
  return "node " .. vim.fn.shellescape(path)
end)
require("util.run").register("typescript", function(path)
  return "npx tsx " .. vim.fn.shellescape(path)
end)

-- tsserver discovers consumers only after their projects have been loaded.
-- Register workspace configs on first attach so references from a shared
-- package also include apps whose files have never been opened in Neovim.
local preloaded = setmetatable({}, { __mode = "k" })
local function preload_projects(client)
  local root = client.config.root_dir
  if preloaded[client] or not root or client:is_stopped() then return end

  local workspace = vim.fn.filereadable(root .. "/pnpm-workspace.yaml") == 1
  if not workspace then
    local ok, package = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(root .. "/package.json"), "\n"))
    end)
    workspace = ok and type(package) == "table" and type(package.workspaces) == "table"
  end
  preloaded[client] = true
  if not workspace then return end

  local function failed(message)
    preloaded[client] = nil
    vim.notify("vtsls: project preload failed: " .. message, vim.log.levels.WARN)
  end

  -- Keep discovery asynchronous and respect ignore files. No hidden buffers,
  -- generated solution config, or changes to the project's compiler options.
  local command = { "rg", "--files", "--null", "-g", "tsconfig.json", "-g", "jsconfig.json" }
  for _, dir in ipairs({ "node_modules", ".git", "dist", "build", "coverage", ".output", ".wxt" }) do
    vim.list_extend(command, { "-g", "!" .. dir .. "/**", "-g", "!**/" .. dir .. "/**" })
  end
  local ok, err = pcall(vim.system, command, { cwd = root }, vim.schedule_wrap(function(result)
    if client:is_stopped() then return end
    if result.code ~= 0 and result.code ~= 1 then
      failed(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "config discovery failed")
      return
    end
    local configs = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
    if #configs < 2 then return end
    table.sort(configs)
    local files = vim.tbl_map(function(file) return { fileName = root .. "/" .. file } end, configs)
    local sent = client:request("workspace/executeCommand", {
      command = "typescript.tsserverRequest",
      arguments = { "openExternalProject", {
        -- An identifier for tsserver's in-memory project group, not a disk file.
        projectFileName = root .. "/.nvim-vtsls-projects",
        rootFiles = files,
        options = vim.empty_dict(),
      } },
    }, function(request_err, response)
      if client:is_stopped() then return end
      if request_err or type(response) ~= "table" or response.success ~= true then
        failed(request_err and request_err.message or "tsserver did not load the projects")
      end
    end)
    if not sent then failed("language server rejected the request") end
  end))
  if not ok then failed(tostring(err)) end
end

---Entry point for js-debug, preferring a build that can debug browser extensions.
---
---Upstream closed browser-extension support as out-of-scope
---(microsoft/vscode-js-debug#945: "I'm surprised it works at all"), so mason's
---build attaches to `page` targets only and never pauses in extension code.
---huiyu/vscode-js-debug carries the community PR #2361 on top of upstream and is
---published in the same layout, so it drops in where mason's copy would go:
---
---    mkdir -p ~/.local/share/nvim/js-debug-webext
---    curl -L https://github.com/huiyu/vscode-js-debug/releases/latest/download/js-debug-dap-webext.tar.gz \
---      | tar -xz -C ~/.local/share/nvim/js-debug-webext
---
---It is a superset -- ordinary page and Node debugging are unaffected -- so a
---machine that has not installed it simply loses extension support rather than
---breaking. See docs/DIAGNOSTICS.md and spikes/chrome-extension-dap.
---@return string[] command and its leading arguments
local function js_debug_command()
  local webext = vim.fn.stdpath("data") .. "/js-debug-webext/src/dapDebugServer.js"
  if vim.uv.fs_stat(webext) then return { "node", webext } end
  return { vim.fn.stdpath("data") .. "/mason/bin/js-debug-adapter" }
end

-- js-debug speaks DAP over a TCP port it is told to listen on; nvim-dap fills
-- `${port}` in both places and starts the resolved binary.
local function js_debug_adapter()
  local command = js_debug_command()
  return {
    type = "server",
    host = "127.0.0.1",
    port = "${port}",
    executable = {
      command = command[1],
      args = vim.list_extend(vim.list_slice(command, 2), { "${port}", "127.0.0.1" }),
    },
  }
end

--- Nearest directory at or above `from` that has vitest installed.
--- A pnpm/npm workspace installs the binary per package, so the closest one
--- wins over the repository root -- debugging a test in apps/extension must run
--- that package's vitest, not a hoisted copy with different plugins.
---@param from string directory to start from
---@return string? program path to vitest.mjs
---@return string? root directory that owns the install
local function nearest_vitest(from)
  local dir = from
  while dir and dir ~= "" do
    local candidate = dir .. "/node_modules/vitest/vitest.mjs"
    if vim.uv.fs_stat(candidate) then return candidate, dir end
    local parent = vim.fs.dirname(dir)
    if parent == dir then return nil end
    dir = parent
  end
end

local function debug_file(ctx)
  require("dap").run({ name = "node: current file", type = "pwa-node", request = "launch",
    program = ctx.path, cwd = vim.fs.root(ctx.path, "package.json") or vim.fs.dirname(ctx.path),
    console = "integratedTerminal", skipFiles = { "<node_internals>/**" } })
end

local function debug_test(ctx, file)
  local program, cwd = nearest_vitest(vim.fs.dirname(ctx.path))
  if not program then
    vim.notify("Test debugging needs a project-local Vitest installation", vim.log.levels.WARN)
    return
  end
  local target = ctx.path
  if not file then
    -- Vitest's file:line selection (v3+) handles nested/parameterized tests
    -- without guessing their generated names or regex-escaping descriptions.
    -- nearest_vitest only proves vitest.mjs is there. A dangling pnpm store
    -- link, a bare shim, or a manifest without a version all raise here, and an
    -- E5108 block is precisely what vitest_program() below refuses to produce --
    -- so any failure degrades to the same one-line warning.
    local ok, metadata = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(vim.fs.dirname(program) .. "/package.json"), "\n"))
    end)
    local major = ok and type(metadata) == "table" and type(metadata.version) == "string"
      and tonumber(metadata.version:match("^(%d+)")) or 0
    if major < 3 then
      vim.notify("Nearest-test debugging needs Vitest 3+; use <leader>tF for this file", vim.log.levels.WARN)
      return
    end
    local tree, lang = require("util.dap").syntax(ctx)
    if not tree then return end
    local query = vim.treesitter.query.parse(lang, "(call_expression function: (_) @fn) @call")
    local selected
    for _, match in query:iter_matches(tree, ctx.bufnr, 0, -1) do
      local fn, call = match[1][1], match[2][1]
      local first, _, last = call:range()
      local name = vim.treesitter.get_node_text(fn, ctx.bufnr)
      if first < ctx.line and last >= ctx.line - 1
        and (name:match("^it[%s%.%(]") or name:match("^test[%s%.%(]") or name == "it" or name == "test")
        and call:field("arguments")[1]:named_child_count() >= 2 then
        selected = math.max(selected or 0, first + 1)
      end
    end
    if not selected then
      vim.notify("Place the cursor inside a Vitest test/it call", vim.log.levels.WARN)
      return
    end
    target = target .. ":" .. selected
  end
  require("dap").run({ name = file and "vitest: current file" or "vitest: nearest test",
    type = "pwa-node", request = "launch", program = program, cwd = cwd,
    args = { "run", "--no-file-parallelism", target }, console = "integratedTerminal",
    skipFiles = { "<node_internals>/**", "**/node_modules/**" } })
end

---Resolve vitest for the current buffer, reporting a missing install in one
---line and aborting the session -- raising here would surface as an E5108 block
---with a stack traceback for what is really "install your dependencies".
---@return fun(): string
local function vitest_program()
  return function()
    local from = vim.fn.expand("%:p:h")
    local program = nearest_vitest(from)
    if not program then
      vim.notify("vitest is not installed in any node_modules above " .. from, vim.log.levels.WARN)
      return require("dap").ABORT
    end
    return program
  end
end

---Run from the package that owns the install, so vitest reads that package's
---config rather than a workspace-root one. Only `program` reports and aborts;
---this one falls back silently so a failed launch says its line once.
---@return fun(): string
local function vitest_cwd()
  return function()
    local from = vim.fn.expand("%:p:h")
    local _, root = nearest_vitest(from)
    return root or from
  end
end

--- Nearest extension build output at or above `from`.
--- `${workspaceFolder}` is the editor's cwd -- the repository root in a monorepo
--- -- while the extension lives in a workspace package, so the build output has
--- to be found the same way vitest is: by walking up from the file being
--- debugged.
---@param from string directory to start from
---@return string? path to the unpacked build output
local function nearest_extension_output(from)
  local dir = from
  while dir and dir ~= "" do
    -- WXT's layout. A different bundler would need its own name here.
    local candidate = dir .. "/.output/chrome-mv3-dev"
    if vim.uv.fs_stat(candidate) then return candidate end
    local parent = vim.fs.dirname(dir)
    if parent == dir then return nil end
    dir = parent
  end
end

---Resolve the extension to debug, reporting a missing build in one line rather
---than letting the browser start and attach to nothing.
---@param want "extension"|"profile"
---@return fun(): string
local function extension_output(want)
  return function()
    local from = vim.fn.expand("%:p:h")
    local output = nearest_extension_output(from)
    if not output then
      if want == "extension" then
        vim.notify(
          "No extension build (.output/chrome-mv3-dev) above " .. from .. " -- run the dev build first",
          vim.log.levels.WARN
        )
      end
      return require("dap").ABORT
    end
    -- The profile sits beside the build it belongs to: two projects debugging
    -- at once through one profile corrupt its storage.
    return want == "extension" and output or (vim.fs.dirname(output) .. "/.debug-profile")
  end
end

local function electron_root()
  return vim.fs.root(0, "package.json") or vim.fn.getcwd()
end

local function electron_binary()
  local dir = electron_root()
  while dir do
    local path = dir .. "/node_modules/.bin/electron"
    if vim.fn.executable(path) == 1 then return path end
    local parent = vim.fs.dirname(dir)
    if parent == dir then break end
    dir = parent
  end
  vim.notify("Electron debugging needs electron installed in the project", vim.log.levels.WARN)
  return require("dap").ABORT
end

---Fresh list per filetype: nvim-dap owns these tables and callers may edit them.
---@return table[]
local function js_debug_configurations()
  return {
    {
      name = "electron: main + renderer",
      type = "pwa-node",
      request = "launch",
      cwd = electron_root,
      runtimeExecutable = electron_binary,
      runtimeArgs = { "--remote-debugging-port=9222" },
      args = { "." },
      env = { ELECTRON_RUN_AS_NODE = vim.NIL },
      outputCapture = "std",
      __electron_renderer = true,
    },
    {
      name = "electron: attach renderer (port 9222)",
      type = "pwa-chrome",
      request = "attach",
      port = 9222,
      webRoot = electron_root,
      timeout = 30000,
    },
    {
      name = "electron: attach main",
      type = "pwa-node", request = "attach", cwd = electron_root,
      address = function() return require("util.dap").input("Electron host: ", "127.0.0.1") end,
      port = function() return require("util.dap").port(9230) end,
      sourceMaps = true,
    },
    {
      name = "vitest: current file",
      type = "pwa-node",
      request = "launch",
      program = vitest_program(),
      cwd = vitest_cwd(),
      -- Vitest isolates test files in worker threads by default and a
      -- breakpoint set in the editor never binds inside one.
      args = { "run", "--no-file-parallelism", "${file}" },
      console = "integratedTerminal",
      skipFiles = { "<node_internals>/**", "**/node_modules/**" },
    },
    {
      name = "node: run current file",
      type = "pwa-node",
      request = "launch",
      program = "${file}",
      cwd = "${workspaceFolder}",
      console = "integratedTerminal",
      skipFiles = { "<node_internals>/**" },
    },
    {
      name = "node: attach to process",
      type = "pwa-node",
      request = "attach",
      -- Deferred: requiring dap.utils here would load nvim-dap while this spec
      -- is still being read, defeating its lazy trigger.
      processId = function() return require("dap.utils").pick_process() end,
      cwd = "${workspaceFolder}",
    },
    {
      name = "node: attach by host/port",
      type = "pwa-node", request = "attach", cwd = "${workspaceFolder}",
      address = function() return require("util.dap").input("Node inspector host: ", "127.0.0.1") end,
      port = function() return require("util.dap").port(9229) end,
      sourceMaps = true,
    },
    {
      -- Chrome must already run with --remote-debugging-port=9222 and its own
      -- --user-data-dir; without the latter a second Chrome hands the URL to the
      -- running instance and never opens the port.
      --
      -- Ordinary pages only. Browser-extension debugging is *out-of-scope*
      -- upstream ("I'm surprised it works at all" -- vscode-js-debug#1794), so
      -- extensions belong in Chrome DevTools. vscode-js-debug#2361 is an open
      -- community PR that implements it; spikes/chrome-extension-dap has the
      -- measurements and what it would take.
      name = "chrome: attach (port 9222)",
      type = "pwa-chrome",
      request = "attach",
      port = 9222,
      webRoot = "${workspaceFolder}",
      sourceMaps = true,
    },
    {
      -- Needs the js-debug-webext build (see js_debug_command) -- mason's cannot
      -- pause in extension code at all.
      --
      -- `extensionPath` is the only path this needs: the extension id, which
      -- target to own, and every sourcemap mapping are all derived from it. An
      -- unpacked extension's id is a hash of this directory, so it must be the
      -- BUILD OUTPUT, not the source tree.
      --
      -- Attach, not launch: launch passes --load-extension, which Chrome removed
      -- in 137+. Start Chrome with --remote-debugging-port=9222 and its own
      -- --user-data-dir, load the unpacked extension once, then attach here.
      name = "chrome: debug extension (attach)",
      type = "pwa-chrome",
      request = "attach",
      port = 9222,
      extensionPath = extension_output("extension"),
    },
    {
      -- Nothing to set up: the debugger starts its own Chrome, installs the
      -- extension over CDP and attaches, so a build watcher in a terminal plus
      -- this entry is the whole loop. It also reloads the extension when the
      -- build output changes, which a manually loaded one will not do.
      --
      -- The profile lives beside the build rather than in a shared cache: two
      -- projects debugging at once through one profile corrupt its storage.
      name = "chrome: debug extension (launch)",
      type = "pwa-chrome",
      request = "launch",
      extensionPath = extension_output("extension"),
      userDataDir = extension_output("profile"),
    },
  }
end

return {
  -- Keep the usual numbers/dates/toggles and add JS/TS declaration keywords.
  {
    "monaqa/dial.nvim",
    optional = true,
    opts = function(_, opts)
      local augend = require("dial.augend")
      local declarations = vim.list_extend(vim.deepcopy(opts.augends.default), {
        augend.constant.new({ elements = { "let", "const" }, word = true, cyclic = true }),
      })
      for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
        opts.filetypes[ft] = declarations
      end
    end,
  },

  -- LSP: vtsls (a vscode-tsserver wrapper) for JS/TS, plus ESLint.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        eslint = {
          settings = {
            workingDirectories = { mode = "auto" },
          },
        },
        vtsls = {
          on_attach = preload_projects,
          filetypes = {
            "javascript",
            "javascriptreact",
            "javascript.jsx",
            "typescript",
            "typescriptreact",
            "typescript.tsx",
          },
          settings = {
            complete_function_calls = true,
            vtsls = {
              enableMoveToFileCodeAction = true,
              autoUseWorkspaceTsdk = true,
              experimental = {
                maxInlayHintLength = 30,
                completion = {
                  enableServerSideFuzzyMatch = true,
                },
              },
            },
            typescript = {
              updateImportsOnFileMove = { enabled = "always" },
              suggest = {
                completeFunctionCalls = true,
              },
              inlayHints = {
                enumMemberValues = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                parameterNames = { enabled = "literals" },
                parameterTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                variableTypes = { enabled = false },
              },
            },
          },
        },
      },
      tools = {
        -- prettier is the configured formatter for js/ts/json/yaml/css/etc.;
        -- install it via mason so formatting does not depend on a global PATH binary.
        -- (eslint/cssls and the other servers are installed from `servers` by
        -- mason-lspconfig, so they are not duplicated here.)
        ["prettier"] = {},
      },
    },
  },

  -- Treesitter parsers for the language.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "javascript", "jsdoc", "typescript", "tsx" } },
  },

  -- Formatting via prettier.
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        ["javascript"] = { "prettier" },
        ["javascriptreact"] = { "prettier" },
        ["typescript"] = { "prettier" },
        ["typescriptreact"] = { "prettier" },
      },
    },
  },

  -- Debugging via vscode-js-debug (mason package: js-debug-adapter).
  --
  -- A single adapter binary covers BOTH runtimes: `pwa-node` for Node processes
  -- and `pwa-chrome` for the browser. The runtime is chosen by the launch
  -- config, not by the plugin, which is exactly why debugging belongs to the
  -- *language* rather than to "web" or "node".
  --
  -- The `js` handler below only makes mason install the package: mason-nvim-dap
  -- ships no adapter definition for js-debug (its `mappings/adapters/` has
  -- bash, chrome, codelldb, node2, python … but no `js.lua`), so the handler
  -- registers nothing on its own and the adapters have to be declared here.
  --
  -- Values that depend on the buffer being debugged are functions: this table
  -- is built when the spec is read, long before there is a current file.
  {
    "mfussenegger/nvim-dap",
    opts = function(_, opts)
      opts.handlers = vim.tbl_extend("force", opts.handlers or {}, { js = {} })
      opts.adapters = vim.tbl_extend("force", opts.adapters or {}, {
        ["pwa-node"] = js_debug_adapter(),
        ["pwa-chrome"] = js_debug_adapter(),
      })
      opts.configurations = opts.configurations or {}
      opts.targets = opts.targets or {}
      for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
        opts.configurations[ft] = vim.list_extend(opts.configurations[ft] or {}, js_debug_configurations())
        opts.targets[ft] = { file = debug_file,
          test = function(ctx) debug_test(ctx, false) end,
          test_file = function(ctx) debug_test(ctx, true) end }
      end
      local dap = require("dap")
      -- Start the renderer after Electron's launch succeeds. js-debug retries
      -- its CDP connection while the main process creates its first window.
      dap.listeners.after.launch["electron_renderer"] = function(session, err)
        if err or not session.config.__electron_renderer or session.parent then return end
        dap.run({
          name = "electron: renderer",
          type = "pwa-chrome",
          request = "attach",
          port = 9222,
          webRoot = session.config.cwd,
          timeout = 30000,
        }, { new = true })
      end
    end,
  },
}
