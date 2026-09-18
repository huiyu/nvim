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

---Fresh list per filetype: nvim-dap owns these tables and callers may edit them.
---@return table[]
local function js_debug_configurations()
  return {
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
      extensionPath = "${workspaceFolder}/.output/chrome-mv3-dev",
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
      extensionPath = "${workspaceFolder}/.output/chrome-mv3-dev",
      userDataDir = "${workspaceFolder}/.output/.debug-profile",
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
    opts = {
      handlers = {
        -- Installs js-debug-adapter. Registers no adapter -- see `adapters`.
        ["js"] = {},
      },
      adapters = {
        ["pwa-node"] = js_debug_adapter(),
        ["pwa-chrome"] = js_debug_adapter(),
      },
      configurations = {
        javascript = js_debug_configurations(),
        javascriptreact = js_debug_configurations(),
        typescript = js_debug_configurations(),
        typescriptreact = js_debug_configurations(),
      },
    },
  },
}
