return {
  "iamcco/markdown-preview.nvim",
  ft = "markdown",
  -- Use the plugin's built-in installer to fetch a prebuilt binary,
  -- avoiding a yarn/node build (no `yarn` dependency required).
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  -- Must be `init`, not `config`: plugin/mkdp.vim calls s:init() at source
  -- time and reads g:mkdp_combine_preview *then* to decide whether to install
  -- its BufEnter autocmd. Setting these after load is a no-op.
  init = function()
    -- Reuse one browser tab across markdown buffers instead of one page per
    -- buffer, and re-point it on BufEnter. Together these turn mkdp's
    -- per-buffer preview into "the tab follows whatever markdown file I'm
    -- looking at" — the closest it gets to project-wide preview.
    vim.g.mkdp_combine_preview = 1
    vim.g.mkdp_combine_preview_auto_refresh = 1
    -- Required by combine mode: the default (1) stops the preview when you
    -- leave the markdown buffer, killing the tab we want to keep reusing.
    vim.g.mkdp_auto_close = 0
  end,
  keys = {
    { "<localleader>p", "<cmd>MarkdownPreviewToggle<cr>", desc = "Toggle Markdown Preview", ft = "markdown" },
    -- Entry point from anywhere. mkdp's server exposes no directory index, so
    -- browsing happens on the Neovim side: pick any markdown under cwd, open
    -- it, hand that buffer to mkdp. Not ft-gated, and so on `;` rather than
    -- <localleader>: this is how you *reach* a markdown file, which is what
    -- the `;` prefix is for. <localleader>p toggles the preview once there.
    {
      ";P",
      function()
        -- Inherits hidden/ignored/exclude from the `files` source (snacks.lua).
        -- Extensions are limited to what g:mkdp_filetypes covers; add "mdx"
        -- here only alongside adding it to g:mkdp_filetypes, or the buffer-local
        -- :MarkdownPreview command is never defined.
        Snacks.picker.files({
          ft = { "md", "markdown" },
          confirm = function(picker, item)
            picker:close()
            local path = item and Snacks.picker.util.path(item)
            if not path then return end
            -- Deferred so the picker window is gone before we edit; otherwise
            -- the file can land in the picker's own window.
            vim.schedule(function()
              vim.cmd.edit(vim.fn.fnameescape(path))
              -- Buffer-local, so absent for a file mkdp does not claim; the
              -- pick has still opened the file, which is then the whole result.
              if vim.fn.exists(":MarkdownPreview") ~= 2 then
                vim.notify(("MarkdownPreview is not available for filetype %q (not in g:mkdp_filetypes)")
                  :format(vim.bo.filetype), vim.log.levels.WARN)
                return
              end
              vim.cmd("MarkdownPreview")
            end)
          end,
        })
      end,
      desc = "Browse markdown in cwd → preview",
    },
  },
}
