local t = dofile('tests/helper.lua')
local tmp = vim.fn.tempname() .. ' shared keys'
vim.fn.mkdir(tmp, 'p')
local result = vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-c', 'luafile tests/fixtures/shared_keys.lua', '-c', 'cquit 1' },
{ env = { KEY_TEST_TMP = tmp }, text = true }):wait(15000)
t.eq(result.code, 0, 'one override updates actual Oil, Snacks, Aerial actions and guide without which-key\n' .. (result.stderr or ''))
local complete = vim.fn.filereadable(tmp .. '/result') == 1 and vim.fn.readfile(tmp .. '/result')[1]
t.eq(complete, 'shared-key-contract-complete', 'the isolated host reached every contract check')
vim.fn.delete(tmp, 'rf')
t.done()
