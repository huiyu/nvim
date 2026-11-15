-- Actual editor actions, independent from which-key's renderer.
local M = {}
local choices, views = {}, {}
local defaults = {
  ["toggle_word_wrap"] = { ["key"] = "<leader>uw", ["desc"] = "Toggle word wrap" },
  ["close_window"] = { ["key"] = "sd", ["desc"] = "Close window" },
  ["prev_tab"] = { ["key"] = "<leader><tab>[", ["desc"] = "Prev tab" },
  ["toggle_line_numbers"] = { ["key"] = "<leader>ul", ["desc"] = "Toggle line numbers" },
  ["close_other_windows"] = { ["key"] = "so", ["desc"] = "Close other windows" },
  ["keybinding_guide"] = { ["key"] = "<leader>?", ["desc"] = "Keybinding guide" },
  ["last_tab"] = { ["key"] = "<leader><tab>l", ["desc"] = "Last tab" },
  ["toggle_relative_numbers"] = { ["key"] = "<leader>uL", ["desc"] = "Toggle relative numbers" },
  ["equalize_windows"] = { ["key"] = "s=", ["desc"] = "Equalize windows" },
  ["last_used_buffer_alternate"] = { ["key"] = ";a", ["desc"] = "Last used buffer (alternate)" },
  ["last_used_tab_alternate"] = { ["key"] = "<leader><tab>a", ["desc"] = "Last used tab (alternate)" },
  ["toggle_diagnostics"] = { ["key"] = "<leader>ud", ["desc"] = "Toggle diagnostics" },
  ["quit_all"] = { ["key"] = "<leader>qq", ["desc"] = "Quit all" },
  ["close_other_tabs"] = { ["key"] = "<leader><tab>o", ["desc"] = "Close other tabs" },
  ["toggle_inlay_hints"] = { ["key"] = "<leader>uh", ["desc"] = "Toggle inlay hints" },
  ["force_quit_all"] = { ["key"] = "<leader>qQ", ["desc"] = "Force quit all" },
  ["new_tab_2"] = { ["key"] = "<leader><tab><tab>", ["desc"] = "New tab" },
  ["editor_window_toggle_back"] = { ["key"] = "se", ["desc"] = "Editor window (toggle back)" },
  ["list_all_tabs"] = { ["key"] = "<leader><tab>s", ["desc"] = "List all tabs" },
  ["toggle_treesitter_highlight"] = { ["key"] = "<leader>uT", ["desc"] = "Toggle Treesitter highlight" },
  ["split_below"] = { ["key"] = "ss", ["desc"] = "Split below" },
  ["close_tab"] = { ["key"] = "<leader><tab>d", ["desc"] = "Close tab" },
  ["toggle_autoformat_file"] = { ["key"] = "<leader>uf", ["desc"] = "Toggle autoformat (file)" },
  ["split_right"] = { ["key"] = "sv", ["desc"] = "Split right" },
  ["next_tab"] = { ["key"] = "<leader><tab>]", ["desc"] = "Next tab" },
  ["toggle_dark_light_background"] = { ["key"] = "<leader>ub", ["desc"] = "Toggle dark/light background" },
  ["toggle_autoformat_global"] = { ["key"] = "<leader>uF", ["desc"] = "Toggle autoformat (global)" },
  ["previous_window"] = { ["key"] = "sw", ["desc"] = "Previous window" },
  ["toggle_spelling"] = { ["key"] = "<leader>us", ["desc"] = "Toggle spelling" },
  ["toggle_conceal_level"] = { ["key"] = "<leader>uc", ["desc"] = "Toggle conceal level" },
  ["first_tab"] = { ["key"] = "<leader><tab>f", ["desc"] = "First tab" },
  ["lazy"] = { ["key"] = "<leader>ml", ["desc"] = "Lazy" },
  ["new_tab"] = { ["key"] = "<leader><tab>n", ["desc"] = "New tab" },
  ["toggle_zoom"] = { ["key"] = "sm", ["desc"] = "Toggle zoom" },
}
function M.setup(keys)
  choices = vim.deepcopy(keys or {})
  local choices = vim.tbl_extend("force", vim.deepcopy(defaults), keys and keys.actions or {})

  local bindings = {
    { "lazy", "<cmd>Lazy<cr>",       desc = "Lazy",  mode = "n" },
    { "keybinding_guide", function() M.show() end, desc = "Keybinding guide", mode = "n" },
    { "last_used_buffer_alternate",  "<C-^>",  desc = "Last used buffer (alternate)",  mode = "n" },
    { "quit_all", function() require("editor_core.quit").all() end,     desc = "Quit all",       mode = "n" },
    { "force_quit_all", function() require("editor_core.quit").all(true) end, desc = "Force quit all", mode = "n" },
    { "split_below", "<cmd>split<cr>",               desc = "Split below",         mode = "n" },
    { "split_right", "<cmd>vsplit<cr>",              desc = "Split right",         mode = "n" },
    { "previous_window", "<C-w>p",                       desc = "Previous window",     mode = "n" },
    { "editor_window_toggle_back", "<cmd>WindowFocusEditor<cr>",  desc = "Editor window (toggle back)", mode = "n" },
    { "close_window", "<cmd>WindowCloseCurrent<cr>", desc = "Close window",        mode = "n" },
    { "close_other_windows", "<cmd>WindowCloseOthers<cr>",  desc = "Close other windows", mode = "n" },
    { "equalize_windows", function() require("editor_core.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
    { "toggle_zoom", function() require("editor_core.window").toggle_zoom() end, desc = "Toggle zoom", mode = "n" },
    { "new_tab",     "<cmd>tabnew<cr>",     desc = "New tab" },
    { "new_tab_2", "<cmd>tabnew<cr>",     desc = "New tab", hidden = true },
    { "close_tab",     "<cmd>tabclose<cr>",   desc = "Close tab" },
    { "next_tab",     "<cmd>tabnext<cr>",    desc = "Next tab" },
    { "prev_tab",     "<cmd>tabprev<cr>",    desc = "Prev tab" },
    { "last_tab",     "<cmd>tablast<cr>",    desc = "Last tab" },
    { "first_tab",     "<cmd>tabfirst<cr>",   desc = "First tab" },
    { "last_used_tab_alternate",     "g<Tab>",              desc = "Last used tab (alternate)" },
    { "close_other_tabs",     "<cmd>tabonly<cr>",     desc = "Close other tabs" },
    { "list_all_tabs",     "<cmd>tabs<cr>",        desc = "List all tabs" },
    { "toggle_autoformat_file", function()
      local enabled = vim.b.autoformat ~= false
      vim.b.autoformat = not enabled
      vim.notify("File autoformat " .. (vim.b.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (file)" },
    { "toggle_autoformat_global", function()
      vim.g.autoformat = not vim.g.autoformat
      vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (global)" },
    { "toggle_spelling", function() vim.opt_local.spell = not vim.opt_local.spell:get() end,             desc = "Toggle spelling" },
    { "toggle_word_wrap", function() vim.opt_local.wrap = not vim.opt_local.wrap:get() end,               desc = "Toggle word wrap" },
    { "toggle_line_numbers", function() vim.opt_local.number = not vim.opt_local.number:get() end,           desc = "Toggle line numbers" },
    { "toggle_relative_numbers", function() vim.opt_local.relativenumber = not vim.opt_local.relativenumber:get() end, desc = "Toggle relative numbers" },
    { "toggle_diagnostics", function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end,          desc = "Toggle diagnostics" },
    { "toggle_inlay_hints", function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, desc = "Toggle inlay hints" },
    { "toggle_treesitter_highlight", function()
      if vim.b.ts_highlight then
        vim.treesitter.stop()
      else
        vim.treesitter.start()
      end
    end, desc = "Toggle Treesitter highlight" },
    { "toggle_conceal_level", function()
      local level = vim.o.conceallevel == 0 and 2 or 0
      vim.opt_local.conceallevel = level
      vim.notify("Conceallevel: " .. level)
    end, desc = "Toggle conceal level" },
    { "toggle_dark_light_background", function()
      vim.o.background = vim.o.background == "dark" and "light" or "dark"
    end, desc = "Toggle dark/light background" }  }
    for _, entry in ipairs(bindings) do
      local choice = choices[entry[1]]
      if choice ~= false then
        assert(type(choice) == "table" and type(choice.key) == "string", "Invalid editor action key: " .. entry[1])
        entry[1] = choice.key
        local opts = { desc = choice.desc or entry.desc, silent = entry.silent ~= false, expr = entry.expr, remap = entry.remap }
        vim.keymap.set(entry.mode or "n", entry[1], entry[2], opts)
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
