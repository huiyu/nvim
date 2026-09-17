local function normalize_options(opts)
  local ret = {}
  for name, config in pairs(opts or {}) do
    if type(name) == "number" then
      ret[config] = {}
    elseif type(config) == "function" then
      ret[name] = config()
    else
      ret[name] = config
    end
  end
  return ret
end

return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    -- Single source of truth: install exactly the servers declared across the
    -- lang/ files (nvim-lspconfig `opts.servers`). Adding a server there is
    -- enough — there is no second hand-maintained list to keep in sync.
    opts = function()
      local lspconfig = require("lazy.core.config").plugins["nvim-lspconfig"]
      local lsp_opts = require("lazy.core.plugin").values(lspconfig, "opts", false)
      return {
        -- jdtls is intentionally NOT a `servers` entry (it is started via
        -- nvim-jdtls and installed through java.lua's `tools`), so it is
        -- absent from the derived list and excluded from automatic_enable.
        ensure_installed = vim.tbl_keys(lsp_opts.servers or {}),
        automatic_enable = {
          exclude = { "jdtls" },
        },
      }
    end,
  },
  {
    "neovim/nvim-lspconfig",
    keys = {
      -- Non-LSP keys (global mappings are fine for these)
      { "[[",  function() require("illuminate").goto_prev_reference(false) end, desc = "Prev reference" },
      { "]]",  function() require("illuminate").goto_next_reference(false) end, desc = "Next reference" },
      { "<leader>mm", "<cmd>Mason<cr>",                            desc = "Mason" },
      -- `:LspInfo` was only ever an alias to this checkhealth, and lspconfig
      -- stops defining it on Nvim 0.12 (see the `:lsp restart` note below).
      { "<leader>mi", "<cmd>checkhealth vim.lsp<cr>",              desc = "Lsp Info" },
      -- Servers keep their own project graph, which `checktime` cannot refresh.
      -- After a structural refactor (files moved across packages, a new
      -- tsconfig/package.json root, re-linked workspace symlinks) the buffer is
      -- current but the server still answers from the old graph -- references
      -- come back empty. Restarting the server is the recovery path.
      -- Use the Nvim 0.12 builtin `:lsp restart`, NOT lspconfig's `:LspRestart`:
      -- lspconfig's plugin file returns early when `:lsp` exists, so it never
      -- creates its own Lsp* commands on 0.12.
      { "<leader>mr", "<cmd>lsp restart<cr>",                      desc = "Lsp Restart" },
    },
    opts = {
      servers = {
        ["lua_ls"] = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim", "Snacks" } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
      }
    },
    config = function(_, opts)
      -- Nvim 0.11's default gr* maps (grr, gri, grt, gra, grn, gO) are left
      -- alone on purpose. Every action they provide already has a shorter
      -- binding below -- gd, gr, gb, gy, ,a, ,r and ;s -- so overriding them only
      -- duplicated the same six actions behind a longer prefix. Leaving the
      -- defaults intact keeps stock-Nvim muscle memory working here and keeps
      -- ":help lsp-defaults" an accurate description of this config.

      -- Buffer-local LSP mappings via LspAttach (for non-default keybindings)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local buf = args.buf
          local map = function(lhs, rhs, desc, mode)
            vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc })
          end
          -- reuse_win = false: jump in *this* window even when the target file
          -- is already open elsewhere. Following a call chain means reading
          -- downward from where the cursor is; letting the jump throw focus to
          -- another split loses that thread.
          -- Every jump that starts from the symbol under the cursor lives on
          -- `g`; the fuzzy pickers that need no starting point stay on `;`.
          -- gb and gC take free letters because Vim owns gi/gI (insert) and
          -- Nvim 0.10 owns gc (comment) -- the mnemonic keys were taken, not
          -- the idea. "[LSP]" marks what needs a language server, so a
          -- which-key popup separates these from lexical motions like gf/ge.
          map("gd",  function() Snacks.picker.lsp_definitions({ jump = { reuse_win = false } }) end, "[LSP] Goto Definition")
          -- nowait: without it `gr` sits through the full 'timeoutlen' on every
          -- press, because Nvim's default grr/gri/grt/gra/grn/grx are longer
          -- candidates and Vim has to wait to see which you meant. References
          -- is too frequent to pay a second for. The trade is that the gr*
          -- defaults become unreachable in an LSP buffer -- every one of them
          -- has a shorter binding here (gb, gy, ,a, ,r) and codelens moved to
          -- ,c, so nothing is actually lost. They still work in Visual mode
          -- and in buffers with no client attached.
          vim.keymap.set("n", "gr", function() Snacks.picker.lsp_references() end,
            { buffer = buf, desc = "[LSP] References", nowait = true })
          map("gb",  function() Snacks.picker.lsp_implementations() end,      "[LSP] Goto Implementation (body)")
          map("gy",  function() Snacks.picker.lsp_type_definitions() end,     "[LSP] Goto Type Definition")
          map("gD",  function() vim.lsp.buf.declaration() end,                "[LSP] Goto Declaration")
          -- "Who calls this?" -- narrower than gr, which also returns the
          -- declaration and same-named strings. Needs callHierarchyProvider:
          -- clangd, gopls, vtsls and basedpyright have it; lua_ls does not.
          map("gC",  function() Snacks.picker.lsp_incoming_calls() end,       "[LSP] Incoming calls")
          map("K",   function() vim.lsp.buf.hover() end,                      "[LSP] Hover")
          map("gK",  function() vim.lsp.buf.signature_help() end,             "[LSP] Signature Help")
          map(",a", function() vim.lsp.buf.code_action() end, "[LSP] Code action", { "n", "v" })
          -- Replaces the grx that nowait above makes unreachable. gopls defines
          -- real lenses here (generate, test, tidy, govulncheck; see lang/go.lua).
          map(",c", function() vim.lsp.codelens.run() end, "[LSP] Run codelens")
          vim.keymap.set("n", ",r",
            function() return ":IncRename " .. vim.fn.expand("<cword>") end,
            { buffer = buf, desc = "[LSP] Rename", expr = true })
        end,
      })

      -- Register LSP server configs via vim.lsp.config() (Neovim 0.11.3+ / mason-lspconfig v2).
      -- Re-enable after registering settings: mason-lspconfig's automatic_enable
      -- may have enabled the server earlier with empty config, so we re-enable
      -- here to make the just-registered settings actually take effect.
      -- Advertise blink.cmp's enhanced client capabilities to every server
      -- (snippet support, auto-import via resolveSupport/additionalTextEdits,
      -- lazy documentation/detail resolution). blink does not inject these on
      -- its own, and per-server `capabilities` (c/yaml) deep-merge on top.
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(nil, true),
      })

      -- Tripwire for LazyVim/old-lspconfig server keys that this native
      -- vim.lsp.config loader silently ignores (a recurring source of dropped
      -- config — see ruff `keys`, tailwind `filetypes_exclude`, json/yaml
      -- `on_new_config` history). Warn instead of failing silently.
      local UNSUPPORTED_SERVER_KEYS = {
        keys = "use a FileType/LspAttach autocmd",
        filetypes_exclude = "set an explicit `filetypes` list",
        filetypes_include = "set an explicit `filetypes` list",
        on_new_config = "use `before_init`",
        root_pattern = "use `root_markers`/`root_dir`",
      }

      for name, config in pairs(normalize_options(opts.servers)) do
        for key, hint in pairs(UNSUPPORTED_SERVER_KEYS) do
          if config[key] ~= nil then
            vim.notify(
              ("lsp: server %q sets unsupported key %q — %s"):format(name, key, hint),
              vim.log.levels.WARN
            )
          end
        end
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
      end

      -- Auto-install tools (formatters, linters, etc.) via Mason registry
      -- mason-registry: link=https://mason-registry.dev/registry/list
      if opts.tools then
        local mr = require("mason-registry")
        mr.refresh(function()
          for tool, config in pairs(normalize_options(opts.tools)) do
            local ok, p = pcall(mr.get_package, tool)
            if not ok then
              vim.schedule(function()
                vim.notify(("mason: unknown tool %q"):format(tool), vim.log.levels.WARN)
              end)
            elseif not p:is_installed() then
              -- Report async install failures instead of silently no-op'ing.
              p:install(config, function(success, err)
                if not success then
                  vim.schedule(function()
                    vim.notify(
                      ("mason: failed to install %q: %s"):format(tool, tostring(err)),
                      vim.log.levels.ERROR
                    )
                  end)
                end
              end)
            end
          end
        end)
      end
    end,
  },
}
