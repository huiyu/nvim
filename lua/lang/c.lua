-- C / C++ language support, modeled on lang/go.lua and LazyVim's clangd extra.
-- clangd serves both C and C++; works best with a compile_commands.json in the
-- project root (generate via `bear -- make`, CMake `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`,
-- or a `compile_flags.txt`). Without it, clangd falls back to heuristics.

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function(ev)
    -- Switch between source (.c/.cpp) and header (.h/.hpp) via clangd.
    vim.keymap.set("n", "<leader>ch", "<cmd>LspClangdSwitchSourceHeader<cr>",
      { buffer = ev.buf, desc = "Switch Source/Header (C/C++)" })

    -- Compile & run the current file in a split terminal (parity with go.lua's <leader>cx).
    vim.keymap.set("n", "<leader>cx", function()
      vim.cmd("write")
      local src = vim.fn.expand("%:p")
      local out = vim.fn.expand("%:p:r")
      local cc = vim.bo.filetype == "cpp" and "c++" or "cc"
      local cmd = string.format("%s %s -o %s && %s",
        cc, vim.fn.shellescape(src), vim.fn.shellescape(out), vim.fn.shellescape(out))
      vim.cmd("split | terminal " .. cmd)
    end, { buffer = ev.buf, desc = "Compile & run current file" })
  end,
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "c", "cpp" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          -- clangd warns when the LSP offset encoding is ambiguous; pin it.
          capabilities = {
            offsetEncoding = { "utf-16" },
          },
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
          },
          root_markers = {
            "compile_commands.json",
            "compile_flags.txt",
            "configure.ac",
            "Makefile",
            "meson.build",
            "build.ninja",
            ".clangd",
            ".git",
          },
          init_options = {
            usePlaceholders = true,
            completeUnimported = true,
            clangdFileStatus = true,
          },
        },
      },
      tools = {
        ["clang-format"] = {},
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
      },
    },
  },
  {
    -- NOTE: clang-tidy is delivered inline by clangd via the --clang-tidy flag
    -- above (configured through .clang-tidy in the project root). It is NOT a
    -- standalone Mason package, so there is no separate nvim-lint pass here.
    "mfussenegger/nvim-dap",
    opts = {
      handlers = {
        codelldb = {},
      },
    },
  },
}
