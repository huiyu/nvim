# Utility Modules Documentation

This document provides detailed documentation for all utility modules in the Neovim configuration.

## Overview

The utility modules provide enterprise-grade functionality including logging, validation, testing, performance monitoring, and development tools. All modules are designed with error handling, type safety, and comprehensive documentation.

## Core Utilities

### 📝 Logger (`util.logger`)

Structured logging framework with level control and history.

#### Features
- **Leveled Logging**: DEBUG, INFO, WARN, ERROR
- **Message Formatting**: Printf-style string formatting
- **History Tracking**: Keeps recent log entries for debugging
- **Safe Execution**: `safe_call()` for error handling
- **Environment Integration**: Configurable via `NVIM_LOG_LEVEL`

#### API Reference

```lua
local logger = require("util.logger")

-- Set log level
logger.set_level("DEBUG")  -- DEBUG|INFO|WARN|ERROR
local level = logger.get_level()

-- Logging methods
logger.debug("Debug message: %s", variable)
logger.info("Operation completed successfully")
logger.warn("Warning: %s may cause issues", feature)
logger.error("Critical error: %s", error_message)

-- Safe function execution
local success, result = logger.safe_call(function()
  -- Potentially failing operation
  return risky_operation()
end, "operation description")

-- History management
local recent = logger.get_recent(10)    -- Get last 10 entries
logger.show_recent(20)                  -- Print last 20 entries
logger.clear_history()                  -- Clear all history
```

#### Configuration

```bash
# Environment variables
export NVIM_LOG_LEVEL=DEBUG    # Set logging level
export NVIM_DEV=1              # Enable development logging
```

### 🔍 Validator (`util.validate`)

Schema-based configuration validation with type safety.

#### Features
- **Type Validation**: Built-in and custom type validators
- **Schema Support**: Complex validation rules and constraints
- **Plugin Validation**: Lazy.nvim plugin specification validation
- **Custom Validators**: Register your own validation functions
- **Detailed Errors**: Comprehensive error reporting

#### Built-in Types

```lua
-- Basic types
"string", "number", "boolean", "table", "function", "nil"

-- Extended types
"positive_number"     -- > 0
"non_negative_number" -- >= 0
"non_empty_string"    -- Non-empty string
"array"               -- Sequential table
"callable"            -- Function or callable table
"file_path"           -- Valid file path (no ..)
"buffer_number"       -- Valid buffer number
"window_number"       -- Valid window number
```

#### API Reference

```lua
local validate = require("util.validate")

-- Simple validation
validate.assert(value, "string", "parameter_name")

-- Schema validation
local schema = {
  name = "string",
  count = { type = "number", min = 0, max = 100 },
  enabled = "boolean",
  optional_field = { type = "string", optional = true },
  items = { type = "array", validator = function(arr) 
    return #arr > 0 
  end },
}

local valid, errors = validate.config(config, schema)
if not valid then
  print("Validation errors:", table.concat(errors, ", "))
end

-- Plugin validation
local valid, errors = validate.plugin_spec({
  "author/plugin-name",
  lazy = true,
  cmd = "PluginCommand",
})

-- Custom validators
validate.register_validator("email", function(value)
  return type(value) == "string" and value:match("^[^@]+@[^@]+$")
end)

-- Create reusable validator
local my_validator = validate.create_validator(schema, true) -- strict mode
local valid, errors = my_validator(config)
```

#### Complex Schema Example

```lua
local user_schema = {
  id = { type = "positive_number" },
  name = { type = "non_empty_string", min_length = 2, max_length = 50 },
  email = { type = "string", validator = function(email)
    return email:match("^[^@]+@[^@]+%.%w+$")
  end },
  age = { type = "number", min = 0, max = 150, optional = true },
  role = { type = "string", values = {"admin", "user", "guest"} },
  settings = {
    type = "table",
    validator = function(settings)
      return validate.config(settings, {
        theme = "string",
        notifications = "boolean",
      })
    end
  },
}
```

### 🧪 Test Framework (`util.test`)

Lightweight testing framework for configuration validation.

#### Features
- **Test Suites**: Organized test groups with `describe()`
- **Rich Assertions**: Comprehensive assertion library
- **Colored Output**: Visual test results with pass/fail indicators
- **Statistics**: Test count, pass/fail tracking
- **Error Reporting**: Detailed failure information with stack traces

#### API Reference

```lua
local test = require("util.test")

-- Configure test framework
test.setup({
  verbose = true,           -- Show individual test results
  show_stack_trace = true,  -- Include stack traces in errors
})

-- Test structure
test.describe("Feature Name", function()
  test.it("should behave correctly", function()
    -- Test implementation
    test.assert_true(condition)
    test.assert_equal(actual, expected)
  end)
  
  test.xit("skipped test", function()
    -- This test will be skipped
  end)
end)

-- Run tests
local success = test.run()  -- Returns true if all tests pass

-- Statistics
local stats = test.get_stats()
-- {
--   suites = 2,
--   tests = 10,
--   passed = 8,
--   failed = 2,
--   errors = {...}
-- }
```

#### Assertion Library

```lua
-- Boolean assertions
test.assert_true(condition, "optional message")
test.assert_false(condition, "optional message")

-- Equality assertions
test.assert_equal(actual, expected, "optional message")
test.assert_not_equal(actual, not_expected, "optional message")

-- Nil assertions
test.assert_nil(value, "optional message")
test.assert_not_nil(value, "optional message")

-- Type assertions
test.assert_type(value, "string", "optional message")

-- Error assertions
test.assert_error(function()
  error("expected error")
end, "expected error pattern", "optional message")

-- Table assertions
test.assert_table_equal(actual_table, expected_table, "optional message")
```

#### Example Test Suite

```lua
local test = require("util.test")
local my_module = require("my.module")

test.describe("My Module", function()
  test.it("should initialize correctly", function()
    local instance = my_module.new()
    test.assert_not_nil(instance)
    test.assert_type(instance, "table")
  end)
  
  test.it("should validate input", function()
    test.assert_error(function()
      my_module.process(nil)
    end, "expected.*argument")
  end)
  
  test.it("should process data correctly", function()
    local input = { value = 42 }
    local result = my_module.process(input)
    
    test.assert_equal(result.status, "success")
    test.assert_equal(result.value, 42)
  end)
end)
```

### ⚡ Performance Monitor (`util.performance`)

Performance monitoring and profiling utilities.

#### Features
- **Startup Profiling**: Automatic startup time measurement
- **Function Timing**: Time individual function calls
- **Memory Monitoring**: Track memory usage over time
- **Timer Management**: High-resolution timing utilities
- **Module Profiling**: Profile entire modules automatically
- **Reporting**: Comprehensive performance reports

#### API Reference

```lua
local performance = require("util.performance")

-- Manual timing
local timer = performance.start_timer("operation_name")
-- ... do work ...
local duration = timer:stop()  -- Returns milliseconds

-- Function timing
local result, duration = performance.time_function("operation", function(arg1, arg2)
  -- Function implementation
  return some_result
end, arg1, arg2)

-- Startup profiling (automatic with NVIM_PROFILE=1)
performance.profile_startup()
local startup_time = performance.get_startup_time()

-- Memory monitoring
local memory_info = performance.get_memory_info()
-- {
--   lua_memory_kb = 1024,
--   lua_memory_mb = 1.0,
--   timestamp = 1640995200
-- }

performance.monitor_memory(5, 60)  -- Monitor for 60s, 5s intervals

-- Timer statistics
local stats = performance.get_timer_stats("operation_name")
-- {
--   name = "operation_name",
--   count = 10,
--   total = 150.5,
--   average = 15.05,
--   min = 12.1,
--   max = 18.9
-- }

-- Module profiling
local profiled_module = performance.profile_module("util.lsp", {"on_attach", "buf_command"})

-- Reporting
performance.report()  -- Print comprehensive report
performance.clear_timers()  -- Clear all timing data
```

#### Environment Configuration

```bash
# Enable profiling
export NVIM_PROFILE=1
export NVIM_PROFILE_VERBOSE=1

# Automatic commands available:
# :PerfReport
# :PerfClear  
# :PerfMemory [interval] [duration]
```

### 🛠 Development Tools (`util.dev`)

Development utilities and debugging commands.

#### Features
- **Hot Reload**: Reload configuration without restarting
- **Module Management**: Reload individual modules
- **System Information**: Comprehensive environment details
- **Plugin Status**: Monitor plugin loading and performance
- **Validation Tools**: Validate entire configuration
- **Testing Integration**: Run tests from command line

#### API Reference

```lua
local dev = require("util.dev")

-- Module management
dev.reload_module("util.lsp")      -- Reload specific module
dev.reload_config()                -- Reload entire configuration

-- Testing and validation
local success = dev.run_tests()    -- Run all tests
local valid, results = dev.validate_plugins()  -- Validate plugins

-- System information
local info = dev.system_info()     -- Get system details
local stats = dev.plugin_status()  -- Get plugin status

-- Profiling
dev.profile_function("my_operation", function()
  -- Code to profile
end)
```

#### Available Commands

When `NVIM_DEV=1`:

```vim
:DevReload                    " Hot-reload configuration
:DevTest                      " Run all tests
:DevValidate                  " Validate plugins
:DevInfo                      " Show system information
:DevPlugins                   " Plugin status and timing
:DevProfile [duration]        " Performance report/memory monitor
:DevReloadModule <module>     " Reload specific module
```

## String Extensions (`util.string-ext`)

Extended string functionality for Lua.

#### API Reference

```lua
require("util.string-ext")  -- Load extensions

-- String methods (added to string table)
local result = "hello.lua":ends_with(".lua")     -- true
local result = "config":starts_with("con")       -- true
local result = "  hello  ":trim()                -- "hello"
local parts = "a,b,c":split(",")                 -- {"a", "b", "c"}
local empty = "   ":is_empty()                   -- true
```

## LSP Utilities (`util.lsp`)

Enhanced LSP functionality with error handling.

#### Features
- **Safe Attachment**: Error-handled LSP client attachment
- **Action Management**: Dynamic LSP action execution
- **Client Management**: Query and manage LSP clients
- **Command Wrapper**: Safe LSP command execution

#### API Reference

```lua
local lsp = require("util.lsp")

-- Safe LSP attachment
local autocmd_id = lsp.on_attach(function(client, buffer)
  -- Setup LSP for buffer
  print("LSP attached:", client.name)
end, "lua_ls")  -- Optional: specific client name

-- LSP actions (dynamic)
lsp.action["source.organizeImports"]()  -- Organize imports
lsp.action["quickfix"]()                -- Apply quickfix

-- Client management
local available, clients = lsp.is_available()
local client = lsp.get_client("lua_ls")

-- Safe command execution
local success = lsp.buf_command("hover")
local success = lsp.buf_command("definition")
```

## Common Utilities (`util.common`)

Functional programming utilities for table manipulation.

#### API Reference

```lua
local common = require("util.common")

-- Create table wrapper
local tbl = common.table({a = 1, b = 2, c = 3})

-- Chainable operations
local keys = tbl:keys()                    -- Get all keys
local values = tbl:values()                -- Get all values
local doubled = tbl:map(function(k, v)     -- Transform values
  return k, v * 2
end)

-- Query operations
local has_key = tbl:containsKey("a")       -- true
local has_value = tbl:containsValue(2)     -- true
local result = tbl:get()                   -- Get underlying table
```

## File Operations (`util.file`)

Object-oriented file manipulation utilities.

#### API Reference

```lua
local File = require("util.file")

-- Create file object
local file = File:of("lua/config.lua")

-- File operations
local is_dir = file:is_dir()
local module_name = file:to_module()  -- "config"

-- Directory traversal
file:walk(function(f)
  print("Found:", f.path)
end)

-- File filtering
local lua_files = File:of("lua/"):find(function(f)
  return f.path:match("%.lua$") and not f:is_dir()
end)
```

## Window Management (`util.window`)

Advanced window management utilities.

#### API Reference

```lua
local window = require("util.window")

-- Window operations (via autocmds)
-- :WindowCloseOthers  - Close all except current
-- :WindowCloseCurrent - Close current window
```

## Best Practices

### Error Handling

Always use safe operations for potentially failing code:

```lua
local logger = require("util.logger")

local success, result = logger.safe_call(function()
  -- Potentially failing operation
  return risky_function()
end, "operation description")

if not success then
  logger.error("Operation failed: %s", result)
  return nil
end
```

### Input Validation

Validate all inputs to public functions:

```lua
local validate = require("util.validate")

function M.my_function(config, name)
  validate.assert(config, "table", "config")
  validate.assert(name, "non_empty_string", "name")
  
  -- Function implementation
end
```

### Performance Monitoring

Profile performance-critical code:

```lua
local performance = require("util.performance")

function M.expensive_operation(data)
  return performance.time_function("expensive_operation", function()
    -- Implementation
    return process_data(data)
  end)
end
```

### Testing

Write tests for all new functionality:

```lua
local test = require("util.test")

test.describe("My Module", function()
  test.it("should handle edge cases", function()
    local result = my_module.edge_case_function()
    test.assert_not_nil(result)
  end)
end)
```

### Logging

Use structured logging for debugging:

```lua
local logger = require("util.logger")

function M.complex_operation(params)
  logger.debug("Starting complex operation with: %s", vim.inspect(params))
  
  local result = do_work(params)
  
  logger.info("Complex operation completed successfully")
  return result
end
```