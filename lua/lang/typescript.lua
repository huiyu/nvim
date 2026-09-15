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
  -- A single adapter covers BOTH runtimes: `pwa-node` for Node processes and
  -- `pwa-chrome` for the browser. The runtime is selected by the launch config,
  -- not by the plugin, which is exactly why debugging belongs to the *language*
  -- rather than to "web" or "node". The `js` handler makes mason install the
  -- adapter and register the default Node launch/attach configs for JS/TS files.
  --
  -- For TypeScript with source maps or a custom runtime (tsx / ts-node), add a
  -- project-level `.vscode/launch.json`; it is picked up via `dap.ext.vscode`.
  {
    "mfussenegger/nvim-dap",
    opts = {
      handlers = {
        ["js"] = {},
      },
    },
  },
}
