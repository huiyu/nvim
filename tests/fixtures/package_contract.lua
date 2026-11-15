-- Independent consumers: no host runtime and no third-party plugin manager.
local root = assert(vim.env.PACKAGE_TEST_ROOT)
vim.opt.rtp = { vim.env.VIMRUNTIME }
vim.opt.packpath = {}
for _, name in ipairs({ 'editor-core', 'agent-workbench', 'git-review', 'llama-service' }) do
  vim.opt.rtp:append(root .. '/local-plugin/' .. name .. '.nvim')
end
table.insert(package.loaders, 1, function(name)
  assert(not name:match('^config[.%w]*$') and not name:match('^util%.'), 'private host dependency: ' .. name)
end)
local original_system, original_jobstart = vim.system, vim.fn.jobstart
vim.system = function() error('unexpected process during require/setup') end
vim.fn.jobstart = function() error('unexpected job during require/setup') end
local before = #vim.api.nvim_list_wins()
local core, agent, git, model = require('editor_core'), require('agent_workbench'), require('git_review'), require('llama_service')
assert(#vim.api.nvim_list_wins() == before, 'require opened a view')
assert(package.loaded['agent_workbench.state'] == nil, 'require resolved native state')
local declaration = { native = { codex = { args = {} } }, keymaps = false }
agent.setup(declaration)
assert(#agent.options().native.codex.args == 0, 'empty argv must remove all base flags')
declaration.native.codex.args[1] = 'changed'
assert(#agent.options().native.codex.args == 0, 'setup retained the caller list')
  local valid, problem = pcall(core.setup, { behaviors = { autoread = 'yes' } })
  assert(not valid and problem:find('editor_core.behaviors.autoread', 1, true), 'invalid behavior declaration was accepted')
  core.setup({ keymaps = false, behaviors = { input_method = false } })
assert(vim.fn.maparg('ss', 'n') == '', 'keymaps=false installed actions')
local config = { retention = { saved = 3 }, history_limit = false }
git.setup(config)
config.retention.saved = 99
local copy = git.options()
assert(copy.retention.saved == 3 and copy.history_limit == false, 'Git declaration/false semantics changed')
copy.retention.saved = 88
assert(git.options().retention.saved == 3, 'Git public observations are mutable aliases')
  valid, problem = pcall(git.setup, { max_file_size = 'large' })
  assert(not valid and problem:find('git_review.max_file_size', 1, true), 'invalid Git declaration was accepted')
  assert(git.options().retention.saved == 3, 'invalid Git setup corrupted the previous options')
model.setup({ port = 8123, args = {} })
assert(model.config.port == 8123 and #model.config.args == 0, 'model partial/empty argv settings changed')
assert(#agent.sessions() == 0 and not model.ready(), 'setup started a session/model')
assert(package.loaded['lazy'] == nil and package.loaded['snacks'] == nil and package.loaded['codecompanion'] == nil,
'consumer requires optional host integrations')
vim.system, vim.fn.jobstart = original_system, original_jobstart
io.stdout:write('PACKAGE_CONTRACT_OK\n')
vim.cmd('qa!')
