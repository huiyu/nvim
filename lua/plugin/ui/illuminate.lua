return {
  "RRethy/vim-illuminate",
  event = { "BufReadPost", "BufNewFile" },
  -- Same gap as the LSP stack (plugin/lsp/lsp.lua): a buffer that never read
  -- a file loads it on its first filetype instead.
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("user_illuminate_scratch_load", { clear = true }),
      callback = function(args)
        if args.match == "" or vim.bo[args.buf].buftype ~= "" then
          return
        end
        require("lazy").load({ plugins = { "vim-illuminate" } })
        return true
      end,
    })
  end,
  config = function()
    require("illuminate").configure({
      providers = {
        "lsp",
        "treesitter",
        "regex",
      },
      delay = 200,
    })
  end,
}
