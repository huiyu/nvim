# Utility Modules Documentation

This document provides detailed documentation for all utility modules in the Neovim configuration.

## Overview

The utility modules provide focused helpers for logging, LSP, table manipulation, terminals, windows, and running the current file. For diagnostic and debugging workflows (health checks, profiling, LSP/treesitter inspection), see [DIAGNOSTICS.md](DIAGNOSTICS.md).

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