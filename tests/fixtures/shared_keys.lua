local ok, err = xpcall(function()
  -- Fresh host: overrides exist before lazy resolves any consumer's options.
  local api = vim.api
  vim.opt.rtp:prepend(vim.fn.getcwd())
  local keys = dofile('lua/config/keymaps.lua')
  keys.open.vsplit.key = '<C-y>'
  keys.open.split, keys.open.preview = false, false
  keys.core.run_file = nil -- Exercise the independent plugin's fallback key.
  keys.actions.close_window = nil
  keys.actions.toggle_word_wrap.key = '<leader>uW'
  keys.actions.toggle_spelling = false
  package.loaded['config.keymaps'] = keys
  vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/lazy.nvim')
  local lazy = require('lazy')
  local setup = lazy.setup
  lazy.setup = function(opts)
    opts.spec[#opts.spec + 1] = { 'folke/which-key.nvim', enabled = false }
    return setup(opts)
  end
  vim.go.loadplugins = true
  dofile('init.lua')
  vim.o.columns, vim.o.lines = 180, 45
  local function check(value, why) assert(value, why) end
  local function local_map(buf, key, mode)
    return api.nvim_buf_call(buf, function() return vim.fn.maparg(key, mode or 'n', false, true) end)
  end
  check(package.loaded['which-key'] == nil, 'which-key is absent')
  check(vim.fn.maparg('ss', 'n') ~= '', 'editor actions exist without which-key')
  check(vim.fn.maparg(',x', 'n') ~= '' and vim.fn.maparg('sd', 'n') ~= '',
    'omitted core/action choices retain their plugin defaults')
  check(vim.fn.maparg('<leader>uW', 'n') ~= '' and vim.fn.maparg('<leader>uw', 'n') == '',
    'an action remap installs only its chosen key')
  check(vim.fn.maparg('<leader>us', 'n') == '', 'false disables an action')
  local tmp = assert(vim.uv.fs_realpath(vim.env.KEY_TEST_TMP))
  local file = tmp .. '/entry.lua'
  vim.fn.writefile({ 'local function entry() end', 'entry()' }, file)
  require('oil').open(tmp)
  local oil_buf = api.nvim_get_current_buf()
  local row
  check(vim.wait(2000, function()
    for i = 1, api.nvim_buf_line_count(oil_buf) do
      local entry = require('oil').get_entry_on_line(oil_buf, i)
      if entry and entry.name == 'entry.lua' then row = i; return true end
    end
  end, 10), 'real Oil fixture appears')
  check(local_map(oil_buf, '<C-y>').desc == keys.open.vsplit.desc, 'Oil uses the shared key/description')
  check(local_map(oil_buf, '<C-v>').buffer ~= 1 and local_map(oil_buf, '<C-s>').buffer ~= 1,
  'Oil removes both replaced and disabled defaults')
  check(local_map(oil_buf, '<M-p>').buffer ~= 1 and local_map(oil_buf, '<C-y>', 'x').buffer ~= 1,
  'disabled preview and Visual mode remain free')
  api.nvim_win_set_cursor(0, { row, 0 })
  local_map(oil_buf, '<C-y>').callback()
  check(vim.wait(2000, function() return api.nvim_buf_get_name(0) == file end, 10), 'Oil shared key opens the actual file')
  check(vim.fn.winlayout()[1] == 'row', 'Oil opens a vertical split')
  local picker = Snacks.picker({ items = { { text = 'entry.lua', file = file } }, format = 'file' })
  check(vim.wait(2000, function() return picker.list:count() == 1 end, 10), 'real picker has the fixture')
  local input = picker.input.win.buf
  check(local_map(input, '<C-y>').buffer == 1 and local_map(input, '<C-y>', 'i').buffer == 1,
  'picker applies the shared key in Normal and Insert')
  check(local_map(input, '<C-v>').buffer ~= 1 and local_map(input, '<C-s>').buffer ~= 1,
  'picker old defaults are gone')
  api.nvim_set_current_win(picker.input.win.win)
  vim.cmd.stopinsert()
  api.nvim_feedkeys(vim.keycode('<C-y>'), 'xt', false)
  check(vim.wait(2000, function() return picker.closed and api.nvim_buf_get_name(0) == file end, 10),
  'picker shared key opens the actual file')
  vim.cmd.AerialOpen()
  local aerial_buf
  check(vim.wait(3000, function()
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      local buf = api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'aerial' then aerial_buf = buf; return true end
    end
  end, 10), 'real Aerial opens')
  check(local_map(aerial_buf, '<C-y>').desc == keys.open.vsplit.desc, 'Aerial translates the same shared action')
  check(local_map(aerial_buf, '<C-v>').buffer ~= 1 and local_map(aerial_buf, '<C-s>').buffer ~= 1,
  'Aerial removes replaced and disabled defaults')
  vim.cmd.AerialClose()
  require('editor_core.keyguide').show()
  local guide = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  check(guide:find('<C-y>', 1, true) and guide:find(keys.open.vsplit.desc, 1, true), 'generated guide follows the remap')
  check(not guide:find('<C-v>', 1, true), 'guide contains no obsolete open chord')
  check(package.loaded['which-key'] == nil, 'no which-key loaded while exercising actual actions')
  vim.fn.writefile({ 'shared-key-contract-complete' }, tmp .. '/result')
  vim.cmd('qa!')

end, debug.traceback)
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
