-- Exercise project preloading through a real vtsls process, with only the
-- shared declaration open. Loading every source buffer would hide this bug.
-- The same on_attach maps gs (Go to Source Definition), which is followed from
-- a package's .d.ts into its JavaScript at the end.
local t = dofile("tests/helper.lua")
local specs = require("lang.typescript")
local on_attach
for _, spec in ipairs(specs) do
  if spec[1] == "neovim/nvim-lspconfig" then
    on_attach = spec.opts.servers.vtsls.on_attach
  end
end
t.ok(type(on_attach) == "function", "vtsls installs the project preload callback")

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
-- A package whose types and code live apart: gd stops at index.d.ts, gs has
-- to land in index.js.
write("node_modules/srcdef-lib/package.json", { '{"name":"srcdef-lib","main":"index.js","types":"index.d.ts"}' })
write("node_modules/srcdef-lib/index.d.ts", { "export declare function greet(name: string): string;" })
write("node_modules/srcdef-lib/index.js", { "exports.greet = function greet(name) {", "  return 'hi ' + name;", "};" })
local greeting = "packages/rules/src/greeting.ts"
write(greeting, { 'import { greet } from "srcdef-lib";', 'export const out = greet("rules");' })
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

local source_definition ---@type fun(client: vim.lsp.Client)?
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
    on_attach = on_attach,
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

  on_attach(client, buffer)
  vim.wait(100, function() return false end, 20)
  t.eq(calls, 1, label .. ": further attaches do not reload projects")

  local gs = vim.fn.maparg("gs", "n", false, true)
  t.eq(gs.desc, "[LSP] Source definition", label .. ": gs is mapped on attach")
  t.eq(gs.buffer, 1, label .. ": gs is buffer-local, so other buffers keep :sleep")
  if source_definition then source_definition(client) end
  client:stop(true)
  t.ok(vim.wait(3000, function() return vim.lsp.get_client_by_id(id) == nil end, 20),
    label .. ": language server shuts down")
end

-- gs runs once, against the first server. The jump opens index.js, which would
-- start the configured JavaScript servers; this spec drives its own client.
local function source_definition_check(client)
  source_definition = nil
  vim.lsp.enable({ "vtsls", "eslint", "tailwindcss" }, false)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, root .. "/" .. greeting)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(root .. "/" .. greeting))
  vim.bo[buf].modified = false
  vim.api.nvim_set_current_buf(buf)
  vim.lsp.buf_attach_client(buf, client.id)
  t.eq(vim.fn.maparg("gs", "n", false, true).buffer, 1, "gs is mapped in every attached buffer")
  vim.api.nvim_win_set_cursor(0, { 2, 20 }) -- on `greet` in the call
  local target = root .. "/node_modules/srcdef-lib/index.js"
  -- Pressed once: a second answer would jump again and push index.js onto
  -- the jumplist ahead of the call.
  vim.fn.maparg("gs", "n", false, true).callback()
  local landed = vim.wait(20000, function() return vim.api.nvim_buf_get_name(0) == target end, 50)
  t.ok(landed, "gs follows the import into the package's JavaScript, past its .d.ts")
  t.eq(vim.api.nvim_win_get_cursor(0), { 1, 25 }, "gs lands on the function's own name")
  vim.cmd("normal! \15")
  t.eq(vim.api.nvim_get_current_buf(), buf, "Ctrl-o returns to the call, as after gd")
  vim.api.nvim_set_current_buf(buffer)
  for _, b in ipairs({ buf, vim.fn.bufnr(target) }) do
    if b > 0 then vim.api.nvim_buf_delete(b, { force = true }) end
  end
  -- Showing a real file brings up plugin scratch buffers of its own; the next
  -- run's "no extra buffers" counts from here.
  buffers_before = vim.api.nvim_list_bufs()
end
source_definition = source_definition_check

run_server("pnpm workspace")
-- A new client must reload projects. Also cover npm/Yarn's workspace marker.
vim.fn.delete(root .. "/pnpm-workspace.yaml")
write("package.json", { '{"private":true,"workspaces":["apps/*","packages/*"]}' })
run_server("npm/Yarn workspace after restart")

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(buffer, { force = true })
vim.fn.delete(root, "rf")
t.done()
