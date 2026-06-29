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

-- <leader>cx runner (dispatched centrally by util.run; keymap in mappings.lua).
-- "Running" a .tex file means producing a PDF: a one-shot latexmk build. `-cd`
-- makes latexmk chdir into the file's directory so relative \input/\includegraphics
-- resolve. For interactive/continuous compilation prefer VimTeX's <localleader>ll.
require("util.run").register({ "tex", "plaintex" }, function(path)
  return "latexmk -cd -pdf -interaction=nonstopmode -synctex=1 " .. vim.fn.shellescape(path)
end)

-- Buffer-local setup for TeX buffers: a curated set of <leader>c* shortcuts under
-- the which-key "Code" group (mirrors go.lua/python.lua), plus prose-friendly
-- editing. VimTeX's full native map set still lives under <localleader>l (e.g.
-- \ll compile, \lv view, \lt TOC) — these are just the discoverable highlights.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex" },
  group = vim.api.nvim_create_augroup("tex_setup", { clear = true }),
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map("<leader>cb", "<cmd>VimtexCompile<cr>",   "Compile (toggle continuous)")
    map("<leader>cv", "<cmd>VimtexView<cr>",      "View PDF (Skim)")
    map("<leader>cs", "<cmd>VimtexStop<cr>",      "Stop compile")
    map("<leader>ck", "<cmd>VimtexClean<cr>",     "Clean aux files")
    map("<leader>ct", "<cmd>VimtexTocToggle<cr>", "Toggle TOC")
    map("<leader>ce", "<cmd>VimtexErrors<cr>",    "Show errors")

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
    -- VimTeX recommends against lazy-loading: it owns its filetype detection and
    -- inverse-search needs the plugin live before the first PDF<->source sync.
    -- The startup cost is small (heavy autoload stays deferred until a tex buffer).
    lazy = false,
    init = function()
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
