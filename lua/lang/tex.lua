-- LaTeX support: VimTeX (compile/view/edit) + texlab (LSP) + treesitter.
--
-- Division of labor, to avoid two tools fighting over the same job:
--   * VimTeX  -> compilation (latexmk), PDF viewing, SyncTeX, TOC, motions.
--   * texlab  -> LSP intelligence (completion, goto, rename labels) + chktex
--                linting. Its own build/forward-search are DISABLED so it never
--                double-compiles behind VimTeX's back.
--   * conform -> formatting via `latexindent` (ships with MacTeX, already on PATH).
--
-- System deps (Homebrew): `mactex-no-gui` (TeXLive: latexmk/latexindent/chktex)
-- and `--cask skim` (PDF viewer with SyncTeX). texlab is auto-installed by mason
-- (it is an `opts.servers` entry; see lua/plugin/lsp/lsp.lua), so no brew needed.

-- ,x runner (dispatched centrally by util.run; keymap in mappings.lua).
-- "Running" a .tex file means producing a PDF: a one-shot latexmk build. `-cd`
-- makes latexmk chdir into the file's directory so relative \input/\includegraphics
-- resolve. For interactive/continuous compilation prefer ,b or VimTeX's ,Ll.
require("util.run").register({ "tex", "plaintex" }, function(path)
  return "latexmk -cd -pdf -interaction=nonstopmode -synctex=1 " .. vim.fn.shellescape(path)
end)

-- Buffer-local compile/view actions share the comma menu with editing.
-- Uppercase K/E preserve ,k (move up) and ,e... (extract); VimTeX's full
-- command set lives under ,L so ,l (indent) has no longer candidates.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex" },
  group = vim.api.nvim_create_augroup("tex_setup", { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map("<localleader>b", "<cmd>VimtexCompile<cr>",   "Compile (toggle continuous)")
    map("<localleader>v", "<cmd>VimtexView<cr>",      "View PDF (Skim)")
    map("<localleader>s", "<cmd>VimtexStop<cr>",      "Stop compile")
    map("<localleader>K", "<cmd>VimtexClean<cr>",     "Clean aux files")
    map("<localleader>t", "<cmd>VimtexTocToggle<cr>", "Toggle TOC")
    map("<localleader>E", "<cmd>VimtexErrors<cr>",    "Show errors")

    -- LaTeX is prose: soft-wrap at word boundaries and spell-check by default.
    -- Toggle per buffer with <leader>uw (wrap) and <leader>us (spell).
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
  end,
})

return {
  {
    "lervag/vimtex",
    -- v2.18 is the last release before VimTeX raised its Neovim requirement
    -- from 0.10 to 0.12.4. Keep the documented 0.11.3 floor honest instead of
    -- disabling VimTeX's version guard and running an unsupported revision.
    version = "v2.18",
    -- VimTeX recommends against lazy-loading: it owns its filetype detection and
    -- inverse-search needs the plugin live before the first PDF<->source sync.
    -- The startup cost is small (heavy autoload stays deferred until a tex buffer).
    lazy = false,
    init = function()
      vim.g.vimtex_mappings_prefix = "<localleader>L"
      -- Forward search (Neovim -> Skim) and inverse search (Skim -> Neovim).
      -- Requires Skim.app. For inverse search, set in Skim > Preferences > Sync:
      --   Preset:    Custom
      --   Command:   nvim
      --   Arguments: --headless -c "VimtexInverseSearch %line '%file'"
      vim.g.vimtex_view_method = "skim"
      vim.g.vimtex_view_skim_sync = 1     -- jump Skim to the cursor's line on view
      vim.g.vimtex_view_skim_activate = 1 -- bring Skim to the foreground on view

      vim.g.vimtex_compiler_method = "latexmk"
      -- Don't pop the quickfix list for warning-only builds (only real errors).
      vim.g.vimtex_quickfix_open_on_warning = 0
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "latex", "bibtex" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        texlab = {
          settings = {
            texlab = {
              -- VimTeX owns compilation/viewing; keep texlab out of the build loop.
              build = { onSave = false },
              -- Surface chktex style/lint diagnostics on open and save.
              chktex = { onOpenAndSave = true, onEdit = false },
              diagnosticsDelay = 300,
            },
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        tex = { "latexindent" },
      },
    },
  },
}
