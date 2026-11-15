local t = dofile('tests/helper.lua')
local result = vim.system({ vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-l', 'tests/fixtures/package_contract.lua' },
{ env = { PACKAGE_TEST_ROOT = t.root }, text = true }):wait(10000)
t.eq(result.code, 0, 'all local packages configure in a host without private modules/processes\n' .. (result.stderr or ''))
t.ok((result.stdout or ''):find('PACKAGE_CONTRACT_OK', 1, true), 'independent consumer completes every lifecycle/option check')
t.done()
