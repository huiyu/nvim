-- Local ghost-text preferences, independent of the chat providers.
return {
  server = {
    port = 8012,
    server = "llama-server",
    args = { "--fim-qwen-7b-default", "--offline", "-c", "8192", "-np", "1", "--sleep-idle-seconds", "300" },
    model = "ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF",
    recheck = 5000,
  },
  ignore_ft = { "markdown", "text", "gitcommit", "gitrebase" },
  context_window = 8000,
  debounce = 150,
}
