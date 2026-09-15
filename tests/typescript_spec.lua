-- Exercise project preloading through a real vtsls process, with only the
-- shared declaration open. Loading every source buffer would hide this bug.
local t = dofile("tests/helper.lua")
local specs = require("lang.typescript")
local preload
for _, spec in ipairs(specs) do
  if spec[1] == "neovim/nvim-lspconfig" then
    preload = spec.opts.servers.vtsls.on_attach
  end
end
t.ok(type(preload) == "function", "vtsls installs the project preload callback")

local executable = vim.fn.exepath("vtsls")
if executable == "" then executable = vim.fn.stdpath("data") .. "/mason/bin/vtsls" end
if vim.fn.executable(executable) ~= 1 then
  print("SKIP - install vtsls through Mason to run the language-server integration checks")
  t.done()
  return
end

local root = vim.fn.tempname() .. " ts workspace"
local function write(name, lines)
  local file = root .. "/" .. name
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  vim.fn.writefile(lines, file)
end
local config = '{"compilerOptions":{"strict":true,"noEmit":true},"include":["src/**/*.ts"]}'
write("pnpm-workspace.yaml", { "packages:", "  - apps/*", "  - packages/*" })
write("packages/rules/tsconfig.json", { config })
write("apps/extension/tsconfig.json", { config })
local source = "packages/rules/src/expression.ts"
write(source, { "export function compileRule(value: string) { return value.trim(); }" })
for _, name in ipairs({ "match", "category-validation" }) do
  write("apps/extension/src/" .. name .. ".ts", {
    'import { compileRule } from "../../../packages/rules/src/expression";',
    'export const result = compileRule("python");',
  })
end
-- These configs must not be loaded, even though they are inside the root.
vim.fn.mkdir(root .. "/.git", "p")
write(".gitignore", { "ignored-project/" })
for _, dir in ipairs({ "ignored-project", "dist", "apps/extension/build", "node_modules/fixture" }) do
  write(dir .. "/tsconfig.json", { config })
  write(dir .. "/src/index.ts", { "export const ignored = true;" })
end
-- Neovim resolves macOS /var -> /private/var when naming buffers; requests
-- must use that same URI to address the document opened on the server.
root = assert(vim.uv.fs_realpath(root))

local original_buffer = vim.api.nvim_get_current_buf()
local buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buffer, root .. "/" .. source)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.fn.readfile(root .. "/" .. source))
vim.bo[buffer].modified = false
vim.api.nvim_set_current_buf(buffer)
local buffers_before = vim.api.nvim_list_bufs()

local function run_server(label)
  local calls, completed, requested_files = 0, false, {}
  local id = vim.lsp.start({
    name = "vtsls-preload-test",
    cmd = { executable, "--stdio" },
    root_dir = root,
    get_language_id = function() return "typescript" end,
    settings = { typescript = { disableAutomaticTypeAcquisition = true } },
    on_init = function(client)
      local request = client.request
      client.request = function(self, method, params, handler, ...)
        if method == "workspace/executeCommand" and params.command == "typescript.tsserverRequest" then
          calls = calls + 1
          requested_files = params.arguments[2].rootFiles
          local callback = handler
          handler = function(err, response, ...)
            completed = true
            t.ok(not err and response and response.success == true, label .. ": tsserver loads the configs")
            callback(err, response, ...)
          end
        end
        return request(self, method, params, handler, ...)
      end
    end,
    on_attach = preload,
  }, { bufnr = buffer })
  t.ok(id ~= nil, label .. ": language server starts")
  if not id then return end
  local client = vim.lsp.get_client_by_id(id)
  t.ok(vim.wait(15000, function() return completed end, 20), label .. ": preload completes on first attach")
  t.eq(requested_files, {
    { fileName = root .. "/apps/extension/tsconfig.json" },
    { fileName = root .. "/packages/rules/tsconfig.json" },
  }, label .. ": ignores dependencies, build output, and gitignored configs")

  local result, err = client:request_sync("textDocument/references", {
    textDocument = { uri = vim.uri_from_fname(root .. "/" .. source) },
    position = { line = 0, character = 16 },
    context = { includeDeclaration = false },
  }, 10000, buffer)
  t.ok(result ~= nil and not result.err and not err, label .. ": reference request succeeds")
  local paths = {}
  for _, reference in ipairs(result and result.result or {}) do
    paths[vim.fs.basename(vim.uri_to_fname(reference.uri))] = true
  end
  t.eq(paths, { ["match.ts"] = true, ["category-validation.ts"] = true },
    label .. ": shared declaration finds callers in the unopened app")
  t.eq(vim.api.nvim_list_bufs(), buffers_before, label .. ": no extra buffers were opened")
  t.eq(vim.fn.filereadable(root .. "/.nvim-vtsls-projects"), 0, label .. ": no synthetic config file was written")

  preload(client)
  vim.wait(100, function() return false end, 20)
  t.eq(calls, 1, label .. ": further attaches do not reload projects")
  client:stop(true)
  t.ok(vim.wait(3000, function() return vim.lsp.get_client_by_id(id) == nil end, 20),
    label .. ": language server shuts down")
end

run_server("pnpm workspace")
-- A new client must reload projects. Also cover npm/Yarn's workspace marker.
vim.fn.delete(root .. "/pnpm-workspace.yaml")
write("package.json", { '{"private":true,"workspaces":["apps/*","packages/*"]}' })
run_server("npm/Yarn workspace after restart")

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(buffer, { force = true })
vim.fn.delete(root, "rf")
t.done()
