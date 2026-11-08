-- As-you-type AI ghost text from the local model behind util.llama, accepted
-- with <C-l>. It is a service of its own: NVIM_AI_PROVIDER (vi's launch flags) picks
-- the agent and CodeCompanion's backend and never changes where these
-- suggestions come from.
--
-- minuet's llama.cpp recipe sends a /v1/completions prompt with the FIM tokens
-- around the cursor. What differs here was measured against the 7B server:
--   * /infill with the current line's head as `prompt`. The server places it
--     after the FIM middle token, so typing along a line re-evaluates only
--     that line from the KV cache: ~0.35 s per suggestion instead of ~0.6 s.
--   * stream. llama-server notices a dropped connection only when it next
--     writes to it, so the request minuet cancels on each new keystroke would
--     otherwise hold the single slot until it finished.
--   * stop at the newline. One line arrives in a fraction of a second; a
--     multi-line block takes seconds and is out of date by then.

local ignore_ft = { "markdown", "text", "gitcommit", "gitrebase" }

local function cursor_state()
  return {
    buf = vim.api.nvim_get_current_buf(),
    tick = vim.b.changedtick,
    cursor = vim.api.nvim_win_get_cursor(0),
    -- <Esc> at column 0 moves neither of the above. minuet would keep that
    -- reply and draw it at the next Insert, wherever that is.
    mode = vim.fn.mode(),
  }
end

-- Whether this buffer can show suggestions at all, and so is worth an 8 GB
-- server: a UI is attached (headless specs and scripts never show ghost text),
-- it is a file rather than a terminal, picker or panel, and minuet's own
-- per-buffer auto-trigger is on -- set from the filetype exclusions below and
-- flipped by :Minuet virtualtext toggle.
local function wants_server()
  return #vim.api.nvim_list_uis() > 0 and vim.bo.buftype == ""
    and vim.b.minuet_virtual_text_auto_trigger == true
end

-- cursor_state() when the latest request went out.
local sent

--- minuet hands every FIM provider the whole text before the cursor as
--- `prompt` and after it as `suffix`; reshape that into /infill's fields.
local function to_infill(request)
  local body = request.body
  local above, line = body.prompt:match("^(.*\n)([^\n]*)$")
  body.input_prefix = above or ""
  body.prompt = line or body.prompt
  body.input_suffix = body.suffix
  body.suffix, body.model = nil, nil
  sent = cursor_state()
  return request
end

--- minuet draws a reply wherever the cursor is when it arrives, so a reply to
--- a request sent before the user typed or moved shows text meant for another
--- position. Drop it: the keystroke that moved the cursor has already
--- scheduled a fresh request. Whitespace is how to say "no suggestion" --
--- returning nothing makes minuet search the raw reply for the word "error"
--- and report any code containing it as a failed request.
local function text_unless_stale(chunk)
  if not vim.deep_equal(cursor_state(), sent) then return " " end
  return chunk.content
end

return {
  "milanglacier/minuet-ai.nvim",
  event = "InsertEnter",
  cmd = "Minuet",
  config = function()
    local llama = require("util.llama")

    require("minuet").setup({
      provider = "openai_fim_compatible",
      n_completions = 1,
      -- About 2k tokens around the cursor, the size the latency was measured at.
      context_window = 8000,
      -- Requests are local and the next one cancels the last. minuet's
      -- throttle would instead drop the request for where typing stopped.
      throttle = 0,
      debounce = 150,
      notify = "error",
      virtualtext = {
        auto_trigger_ft = { "*" },
        auto_trigger_ignore_ft = ignore_ft,
        keymap = { accept = "<C-l>" },
        -- blink's menu is open for most identifier keystrokes; hiding the
        -- suggestion under it would hide it most of the time.
        show_on_completion_menu = true,
      },
      enable_predicates = {
        function()
          if not wants_server() then return false end
          -- Rechecks every few seconds, which is how a server that another
          -- Nvim started, and that has since stopped, gets noticed.
          llama.ensure()
          return llama.ready()
        end,
      },
      provider_options = {
        openai_fim_compatible = {
          name = "llama.cpp",
          end_point = llama.url("/infill"),
          -- The local server takes no key, but minuet refuses to run without one.
          api_key = function() return "local" end,
          model = "local",
          stream = true,
          optional = { n_predict = 64, top_k = 1, stop = { "\n" }, response_fields = { "content" } },
          template = {
            prompt = function(before) return before end,
            suffix = function(_, after) return after end,
          },
          transform = { to_infill },
          get_text_fn = { stream = text_unless_stale },
        },
      },
    })

    -- minuet marks buffers for auto-trigger on FileType, which has already
    -- fired for everything opened before this first Insert. Replay its own
    -- handler there, so which filetypes qualify stays minuet's decision.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local ft = vim.bo[buf].filetype
      if vim.api.nvim_buf_is_loaded(buf) and ft ~= "" then
        vim.api.nvim_buf_call(buf, function()
          vim.api.nvim_exec_autocmds("FileType", { group = "MinuetVirtualText", pattern = ft, modeline = false })
        end)
      end
    end

    -- Start loading at Insert rather than at the first pause in typing.
    local function ensure()
      if wants_server() then llama.ensure() end
    end
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = vim.api.nvim_create_augroup("user_llama_ensure", { clear = true }),
      callback = ensure,
    })
    ensure()
  end,
}
