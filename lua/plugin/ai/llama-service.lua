local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
return {
  opts = function() return require("config.completion").server end,
  dir = root .. "/local-plugin/llama-service.nvim", name = "llama-service.nvim", main = "llama_service",
}
