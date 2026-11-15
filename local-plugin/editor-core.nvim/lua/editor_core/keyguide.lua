-- Actual editor actions, independent from which-key's renderer.
local M = {}
local choices, views = {}, {}
function M.setup(keys)
  choices = vim.deepcopy(keys or {})
  local overrides = keys and keys.actions or {}

  local bindings = {
    { id = "lazy", key = "<leader>ml", action = "<cmd>Lazy<cr>", desc = "Lazy", mode = "n" },
    { id = "keybinding_guide", key = "<leader>?", action = function() M.show() end, desc = "Keybinding guide", mode = "n" },
    { id = "last_used_buffer_alternate", key = ";a", action = "<C-^>", desc = "Last used buffer (alternate)", mode = "n" },
    { id = "quit_all", key = "<leader>qq", action = function() require("editor_core.quit").all() end, desc = "Quit all", mode = "n" },
    { id = "force_quit_all", key = "<leader>qQ", action = function() require("editor_core.quit").all(true) end, desc = "Force quit all", mode = "n" },
    { id = "split_below", key = "ss", action = "<cmd>split<cr>", desc = "Split below", mode = "n" },
    { id = "split_right", key = "sv", action = "<cmd>vsplit<cr>", desc = "Split right", mode = "n" },
    { id = "previous_window", key = "sw", action = "<C-w>p", desc = "Previous window", mode = "n" },
    { id = "editor_window_toggle_back", key = "se", action = "<cmd>WindowFocusEditor<cr>", desc = "Editor window (toggle back)", mode = "n" },
    { id = "close_window", key = "sd", action = "<cmd>WindowCloseCurrent<cr>", desc = "Close window", mode = "n" },
    { id = "close_other_windows", key = "so", action = "<cmd>WindowCloseOthers<cr>", desc = "Close other windows", mode = "n" },
    { id = "equalize_windows", key = "s=", action = function() require("editor_core.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
    { id = "toggle_zoom", key = "sm", action = function() require("editor_core.window").toggle_zoom() end, desc = "Toggle zoom", mode = "n" },
    { id = "new_tab", key = "<leader><tab>n", action = "<cmd>tabnew<cr>", desc = "New tab" },
    { id = "new_tab_2", key = "<leader><tab><tab>", action = "<cmd>tabnew<cr>", desc = "New tab" },
    { id = "close_tab", key = "<leader><tab>d", action = "<cmd>tabclose<cr>", desc = "Close tab" },
    { id = "next_tab", key = "<leader><tab>]", action = "<cmd>tabnext<cr>", desc = "Next tab" },
    { id = "prev_tab", key = "<leader><tab>[", action = "<cmd>tabprev<cr>", desc = "Prev tab" },
    { id = "last_tab", key = "<leader><tab>l", action = "<cmd>tablast<cr>", desc = "Last tab" },
    { id = "first_tab", key = "<leader><tab>f", action = "<cmd>tabfirst<cr>", desc = "First tab" },
    { id = "last_used_tab_alternate", key = "<leader><tab>a", action = "g<Tab>", desc = "Last used tab (alternate)" },
    { id = "close_other_tabs", key = "<leader><tab>o", action = "<cmd>tabonly<cr>", desc = "Close other tabs" },
    { id = "list_all_tabs", key = "<leader><tab>s", action = "<cmd>tabs<cr>", desc = "List all tabs" },
    { id = "toggle_autoformat_file", key = "<leader>uf", action = function()
      local enabled = vim.b.autoformat ~= false
      vim.b.autoformat = not enabled
      vim.notify("File autoformat " .. (vim.b.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (file)" },
    { id = "toggle_autoformat_global", key = "<leader>uF", action = function()
      vim.g.autoformat = not vim.g.autoformat
      vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (global)" },
    { id = "toggle_spelling", key = "<leader>us", action = function() vim.opt_local.spell = not vim.opt_local.spell:get() end, desc = "Toggle spelling" },
    { id = "toggle_word_wrap", key = "<leader>uw", action = function() vim.opt_local.wrap = not vim.opt_local.wrap:get() end, desc = "Toggle word wrap" },
    { id = "toggle_line_numbers", key = "<leader>ul", action = function() vim.opt_local.number = not vim.opt_local.number:get() end, desc = "Toggle line numbers" },
    { id = "toggle_relative_numbers", key = "<leader>uL", action = function() vim.opt_local.relativenumber = not vim.opt_local.relativenumber:get() end, desc = "Toggle relative numbers" },
    { id = "toggle_diagnostics", key = "<leader>ud", action = function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end, desc = "Toggle diagnostics" },
    { id = "toggle_inlay_hints", key = "<leader>uh", action = function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, desc = "Toggle inlay hints" },
    { id = "toggle_treesitter_highlight", key = "<leader>uT", action = function()
      if vim.b.ts_highlight then
        vim.treesitter.stop()
      else
        vim.treesitter.start()
      end
    end, desc = "Toggle Treesitter highlight" },
    { id = "toggle_conceal_level", key = "<leader>uc", action = function()
      local level = vim.o.conceallevel == 0 and 2 or 0
      vim.opt_local.conceallevel = level
      vim.notify("Conceallevel: " .. level)
    end, desc = "Toggle conceal level" },
    { id = "toggle_dark_light_background", key = "<leader>ub", action = function()
      vim.o.background = vim.o.background == "dark" and "light" or "dark"
    end, desc = "Toggle dark/light background" },
  }
  for _, entry in ipairs(bindings) do
    local choice = overrides[entry.id]
    if choice ~= false then
      local key, desc = entry.key, entry.desc
      if choice ~= nil then
        assert(type(choice) == "table" and type(choice.key) == "string", "Invalid editor action key: " .. entry.id)
        key, desc = choice.key, choice.desc or desc
      end
      vim.keymap.set(entry.mode or "n", key, entry.action, { desc = desc, silent = true })
    end
  end
end

-- Render the bindings their owners actually installed, including live descs.
-- Shared open actions are also shown outside picker/file-manager buffers.
function M.show()
  local api = vim.api
  local tab = api.nvim_get_current_tabpage()
  if views[tab] and api.nvim_win_is_valid(views[tab]) then api.nvim_set_current_win(views[tab]); return end
  local lines = { "Trigger Key Reference", "", ";  Go to a file/symbol", ",  Act on this file/view", "s  Arrange windows", "<leader>  Global domains", "", "Shared open actions" }
  for _, name in ipairs({ "split", "vsplit", "tab", "preview" }) do
    local action = choices.open and choices.open[name]
    if action then lines[#lines + 1] = string.format("  %-22s %s", action.key, action.desc) end
  end
  for _, mode in ipairs({ "n", "x", "i", "t" }) do
    local maps = {}
    for _, scope in ipairs({ api.nvim_get_keymap(mode), api.nvim_buf_get_keymap(0, mode) }) do
      for _, mapping in ipairs(scope) do if mapping.desc and mapping.desc ~= "" then maps[mapping.lhs] = mapping.desc end end
    end
    lines[#lines + 1], lines[#lines + 2] = "", "Mode: " .. mode
    local keys = vim.tbl_keys(maps)
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = string.format("  %-28s %s", key, maps[key]) end
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "nofile", "wipe", false
  local width = math.max(1, math.min(110, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))
  local win = api.nvim_open_win(buf, true, { relative = "editor", style = "minimal", border = "rounded",
  width = width, height = height, row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
  col = math.max(0, math.floor((vim.o.columns - width) / 2)), title = " Key Reference " })
  views[tab] = win
  local function close() if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end end
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close keybinding guide" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close keybinding guide" })
end
return M
