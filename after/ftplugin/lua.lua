vim.cmd("set whichwrap+=<,>,[,],h,l")
vim.cmd([[set iskeyword+=-]])
vim.opt_local.formatoptions:remove({ "c", "r", "o" })
