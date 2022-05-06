local status_ok, transparent = pcall(require, "transparent")

if not status_ok then
  return
end

transparent.setup({
  enable = true,
  extra_groups = {
    "BufferLineTabClose",
    "BufferlineBufferSelected",
    "BufferLineFill",
    "BufferLineBackground",
    "BufferLineSeparator",
    "BufferLineIndicatorSelected",
  },
})

vim.api.nvim_command("highlight NormalFloat guibg=none")
