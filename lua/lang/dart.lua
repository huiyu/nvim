local function root()
  return vim.fs.root(0, "pubspec.yaml") or vim.fn.getcwd()
end

local function current_file()
  -- Match the canonical buffer path dap uses for breakpoints (/tmp may be a
  -- symlink on macOS); Dart treats the two spellings as different libraries.
  return vim.api.nvim_buf_get_name(0)
end

-- Prefer the project's FVM SDK; otherwise use the SDK already on PATH.
local function adapter(tool, test)
  return function(callback, config)
    local cwd = config.cwd or root()
    local fvm = vim.fs.find(".fvm", { path = cwd, upward = true, type = "directory" })[1]
    local command = fvm and (fvm .. "/flutter_sdk/bin/" .. tool) or tool
    if vim.fn.executable(command) ~= 1 then command = tool end
    if vim.fn.executable(command) ~= 1 then
      vim.notify("Dart/Flutter debugging needs " .. tool .. " on PATH or .fvm/flutter_sdk", vim.log.levels.WARN)
      return
    end
    local args = { "debug_adapter" }
    if test then table.insert(args, "--test") end
    callback({ type = "executable", command = command, args = args, options = { cwd = cwd } })
  end
end

local function device_args()
  local ok, device = pcall(vim.fn.input, "Flutter device ID (empty = auto): ")
  if not ok then return require("dap").ABORT end
  return vim.trim(device) == "" and {} or { "-d", vim.trim(device) }
end

local function service_uri(required)
  local prompt = required and "Dart VM service URI: " or "Flutter VM service URI (empty = device discovery): "
  local ok, uri = pcall(vim.fn.input, prompt)
  if not ok then return require("dap").ABORT end
  uri = vim.trim(uri)
  if uri == "" then return required and require("dap").ABORT or vim.NIL end
  if not uri:match("^https?://") and not uri:match("^wss?://") then
    vim.notify("Paste the full VM service http(s):// or ws(s):// URI, including its token", vim.log.levels.WARN)
    return require("dap").ABORT
  end
  return uri
end

local function hot_request(method)
  return function()
    local session = require("dap").session()
    if not session or (session.config.type ~= "flutter" and session.config.type ~= "dart") then
      vim.notify("Start a Dart/Flutter app session first", vim.log.levels.INFO)
      return
    end
    if method == "hotRestart" and session.config.type ~= "flutter" then
      vim.notify("Use <leader>dR to restart a Dart CLI session", vim.log.levels.INFO)
      return
    end
    session:request(method, { reason = "manual" }, function(err)
      if err then vim.notify(tostring(err), vim.log.levels.ERROR) end
    end)
  end
end

local function debug_target(ctx, kind)
  local cwd = vim.fs.root(ctx.path, "pubspec.yaml") or vim.fs.dirname(ctx.path)
  local flutter = false
  if vim.fn.filereadable(cwd .. "/pubspec.yaml") == 1 then
    for _, line in ipairs(vim.fn.readfile(cwd .. "/pubspec.yaml")) do
      if line:gsub("#.*", ""):match("^%s+sdk:%s*['\"]?flutter['\"]?%s*$") then flutter = true end
    end
  end
  local test = kind ~= "file"
  local program = ctx.path
  if kind == "test" then
    local tree, lang = require("util.dap").syntax(ctx)
    if not tree then return end
    local query = vim.treesitter.query.parse(lang,
      "(expression_statement (identifier) @name (selector (argument_part (arguments)))) @call")
    local selected
    for _, match in query:iter_matches(tree, ctx.bufnr, 0, -1) do
      local name, call = match[1][1], match[2][1]
      local first, _, last = call:range()
      local text = vim.treesitter.get_node_text(name, ctx.bufnr)
      if (text == "test" or text == "testWidgets") and first < ctx.line and last >= ctx.line - 1 then
        selected = math.max(selected or 0, first + 1)
      end
    end
    if not selected then
      vim.notify("Place the cursor inside a Dart test/testWidgets call", vim.log.levels.WARN)
      return
    end
    -- package:test's path query also works in flutter test, and selects the
    -- declaration rather than trying to reconstruct nested/dynamic names.
    program = program .. "?line=" .. selected
  end
  local adapter_type = (flutter and "flutter" or "dart") .. (test and "_test" or "")
  require("dap").run({ name = adapter_type .. ": " .. kind, type = adapter_type, request = "launch",
    program = program, cwd = cwd, toolArgs = flutter and not test and device_args or nil })
end

return {
  {
    "mfussenegger/nvim-dap",
    keys = {
      { "<localleader>dr", hot_request("hotReload"), ft = "dart", desc = "Dart/Flutter Hot Reload" },
      { "<localleader>dR", hot_request("hotRestart"), ft = "dart", desc = "Flutter Hot Restart" },
    },
    opts = {
      targets = { dart = {
        file = function(ctx) debug_target(ctx, "file") end,
        test = function(ctx) debug_target(ctx, "test") end,
        test_file = function(ctx) debug_target(ctx, "test_file") end,
      } },
      adapters = {
        dart = adapter("dart"), dart_test = adapter("dart", true),
        flutter = adapter("flutter"), flutter_test = adapter("flutter", true),
      },
      configurations = {
        dart = {
          { name = "dart: current file", type = "dart", request = "launch", program = current_file, cwd = root },
          { name = "dart: attach to VM service", type = "dart", request = "attach", cwd = root,
            vmServiceUri = function() return service_uri(true) end },
          { name = "dart: test current file", type = "dart_test", request = "launch", program = current_file, cwd = root },
          { name = "flutter: launch app", type = "flutter", request = "launch",
            program = function() return root() .. "/lib/main.dart" end, cwd = root, toolArgs = device_args },
          { name = "flutter: attach to running app", type = "flutter", request = "attach", cwd = root,
            toolArgs = device_args, vmServiceUri = function() return service_uri(false) end },
          { name = "flutter: test current file", type = "flutter_test", request = "launch", program = current_file, cwd = root },
        },
      },
    },
  },
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "dart" } } },
}
