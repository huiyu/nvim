# Neovim Configuration

A modern, enterprise-grade Neovim configuration built with Lua and organized using the lazy.nvim plugin manager. Features comprehensive error handling, logging, testing, and performance monitoring for a robust development experience.

## Features

### 🎨 User Interface
- **Solarized** color scheme for a pleasant coding experience
- **Lualine** - Beautiful and informative status line
- **Treesitter** - Advanced syntax highlighting and code parsing
- **Noice** - Enhanced UI for messages, cmdline and popupmenu
- **Colorizer** - Real-time color highlighting
- **Todo Comments** - Highlight and search for todo comments
- **Illuminate** - Automatically highlight word under cursor

### ⚡ Editor Enhancement
- **Telescope** - Fuzzy finder for files, grep, and more
- **Flash** - Fast navigation with search labels
- **WhichKey** - Interactive keybinding help
- **Autopairs** - Automatic bracket/quote pairing
- **Autotag** - Automatic HTML/XML tag management
- **Comment** - Smart commenting with treesitter
- **Surround** - Easy manipulation of surrounding characters
- **Snacks** - Collection of useful utilities
- **Persistence** - Session management
- **ToggleTerm** - Integrated terminal

### 🛠 LSP & Development
- **Mason** - LSP server, DAP server, linter, and formatter manager
- **Nvim-cmp** - Powerful autocompletion engine
- **Copilot** - AI-powered code completion
- **Conform** - Code formatting
- **DAP** - Debug adapter protocol support
- **Test** - Testing integration

### 📝 Language Support
- **Bash** - Shell scripting
- **Go** - Go programming language
- **Python** - Python development
- **Java** - Java development
- **Web** - HTML, CSS, JavaScript, TypeScript, React

### 🔧 Version Control
- **Gitsigns** - Git integration with signs, hunk actions, and blame

### 🛡️ Enterprise Features
- **Comprehensive Logging** - Structured logging with level control and history
- **Error Handling** - Robust error recovery and user-friendly error messages
- **Configuration Validation** - Schema-based validation for all configurations
- **Testing Framework** - Built-in testing for configuration components
- **Performance Monitoring** - Startup time analysis and memory usage tracking
- **Development Tools** - Hot-reload, debugging commands, and system information

## Structure

```
~/.config/nvim/
├── init.lua                 # Entry point
├── lazy-lock.json          # Plugin version lock file
├── after/
│   └── ftplugin/           # Filetype-specific configurations
├── lua/
│   ├── autocmds.lua        # Auto commands
│   ├── bootstrap.lua       # Lazy.nvim setup
│   ├── icons.lua           # Icon definitions
│   ├── mappings.lua        # Key mappings
│   ├── options.lua         # Vim options
│   ├── lang/               # Language-specific configurations
│   ├── plugin/             # Plugin configurations
│   │   ├── editor/         # Editor enhancement plugins
│   │   ├── lsp/            # LSP and completion plugins
│   │   ├── ui/             # UI and theme plugins
│   │   └── vcs/            # Version control plugins
│   └── util/               # Utility modules
│       ├── logger.lua      # Logging framework
│       ├── validate.lua    # Configuration validation
│       ├── test.lua        # Testing framework
│       ├── performance.lua # Performance monitoring
│       ├── dev.lua         # Development utilities
│       ├── string-ext.lua  # String extensions
│       ├── lsp.lua         # LSP utilities
│       ├── common.lua      # Common utilities
│       ├── file.lua        # File operations
│       └── window.lua      # Window management
├── test/                   # Test files
│   └── config_test.lua     # Configuration tests
└── plugin/                 # Additional plugin files
```

## Installation

1. **Backup existing configuration** (if any):
   ```bash
   mv ~/.config/nvim ~/.config/nvim.backup
   ```

2. **Clone this configuration**:
   ```bash
   git clone <repository-url> ~/.config/nvim
   ```

3. **Start Neovim**:
   ```bash
   nvim
   ```

   Lazy.nvim will automatically install all plugins on first launch.

## Key Features

- **Lazy Loading**: Plugins are loaded only when needed for optimal startup time
- **Modular Structure**: Well-organized configuration split into logical modules
- **Language Support**: Comprehensive support for multiple programming languages
- **Modern Tools**: Uses the latest and most popular Neovim plugins
- **Performance Optimized**: Disabled unnecessary built-in plugins for better performance
- **Enterprise-Grade**: Logging, error handling, validation, and testing built-in
- **Developer Friendly**: Hot-reload, debugging tools, and comprehensive documentation

## Requirements

- **Neovim** >= 0.9.0
- **Git** for plugin management
- **Node.js** for LSP servers and tools
- **Python** for Python support
- **Go** for Go language support
- **Java** for Java development
- A **Nerd Font** for proper icon display

### Optional Environment Variables

- `NVIM_DEV=1` - Enable development mode with extra tools and commands
- `NVIM_PROFILE=1` - Enable performance profiling and startup time measurement
- `NVIM_PROFILE_VERBOSE=1` - Show verbose profiling information
- `NVIM_LOG_LEVEL=DEBUG|INFO|WARN|ERROR` - Set logging level (default: INFO)

## Development Tools & Commands

This configuration includes a comprehensive set of development tools for maintaining and debugging the configuration.

### 🛠 Development Commands

Enable development mode with `export NVIM_DEV=1`, then use these commands:

| Command | Description |
|---------|-------------|
| `:DevReload` | Hot-reload the entire configuration |
| `:DevTest` | Run all configuration tests |
| `:DevValidate` | Validate all plugin configurations |
| `:DevInfo` | Show detailed system information |
| `:DevPlugins` | Display plugin loading status and timing |
| `:DevProfile [duration]` | Show performance report or monitor memory |
| `:DevReloadModule <module>` | Reload a specific module |

### 📊 Performance Commands

Enable profiling with `export NVIM_PROFILE=1`:

| Command | Description |
|---------|-------------|
| `:PerfReport` | Show comprehensive performance report |
| `:PerfClear` | Clear all performance data |
| `:PerfMemory [interval] [duration]` | Monitor memory usage over time |

### 🧪 Testing Commands

| Command | Description |
|---------|-------------|
| `:TestRun` | Execute all configuration tests |
| `:TestReset` | Reset test statistics |

### 📝 Logging Features

The configuration includes a structured logging system:

```lua
local logger = require("util.logger")

logger.info("Configuration loaded successfully")
logger.debug("Debug information: %s", some_variable)
logger.warn("Warning: %s", warning_message)
logger.error("Error occurred: %s", error_message)

-- Safe function execution with automatic error logging
local success, result = logger.safe_call(function()
  -- Your code here
  return some_result
end, "operation description")
```

### 🔍 Configuration Validation

Validate configurations using schemas:

```lua
local validate = require("util.validate")

local schema = {
  name = "string",
  count = { type = "number", min = 0, max = 100 },
  enabled = "boolean",
  items = "array",
}

local valid, errors = validate.config(my_config, schema)
if not valid then
  print("Validation errors:", table.concat(errors, ", "))
end
```

### ⚡ Performance Monitoring

Monitor function performance:

```lua
local performance = require("util.performance")

-- Time a function
local result, duration = performance.time_function("my_operation", function()
  -- Your code here
  return some_result
end)

-- Use manual timers
local timer = performance.start_timer("custom_operation")
-- ... do work ...
local duration = timer:stop()
```

## Customization

The configuration is designed to be easily customizable:

### 🔧 Adding Language Support

To add support for a new language:

1. **Create a language configuration file** in `lua/lang/`:
   ```lua
   -- lua/lang/rust.lua
   return {
     {
       "simrat39/rust-tools.nvim",
       ft = "rust",
       dependencies = { "neovim/nvim-lspconfig" },
       config = function()
         require("rust-tools").setup()
       end,
     }
   }
   ```

2. **The file will be automatically loaded** by the bootstrap system

### ⚙️ Plugin Management

**Adding a new plugin:**
```lua
-- lua/plugin/editor/new-plugin.lua
return {
  "author/plugin-name",
  lazy = true,  -- Enable lazy loading
  cmd = "PluginCommand",  -- Load on command
  keys = { "<leader>p" }, -- Load on key mapping
  config = function()
    -- Plugin configuration
  end,
}
```

**Removing a plugin:**
- Delete the plugin file from `lua/plugin/*/`
- Run `:Lazy clean` to remove unused plugins

### 🎯 Key Mapping Customization

Modify `lua/mappings.lua` to customize key bindings:

```lua
-- Add new mappings to the return table
{ "<leader>x", "<cmd>YourCommand<cr>", desc = "Your description" }

-- Modify existing mappings by changing the key or command
{ "<leader>f", "<cmd>YourFinder<cr>", desc = "Custom finder" }
```

### 🎨 UI Customization

**Changing colorscheme:**
```lua
-- lua/plugin/ui/your-theme.lua
return {
  "your-theme/nvim",
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("your-theme")
  end,
}
```

**Customizing statusline:**
- Edit `lua/plugin/ui/lualine.lua`
- Modify the sections and components

### 🔍 LSP Configuration

**Adding a new LSP server:**
```lua
-- lua/plugin/lsp/lsp.lua - add to servers table
["your_lsp"] = {
  settings = {
    -- Your LSP-specific settings
  },
}
```

**Custom formatting:**
```lua
-- lua/plugin/lsp/conform.lua - add to formatters_by_ft
your_filetype = { "your_formatter" }
```

### 📁 Directory Structure for Custom Additions

```
lua/
├── lang/
│   └── your-language.lua     # Language-specific configs
├── plugin/
│   ├── editor/
│   │   └── your-editor.lua   # Editor enhancement plugins
│   ├── lsp/
│   │   └── your-lsp.lua      # LSP-related plugins
│   ├── ui/
│   │   └── your-ui.lua       # UI and theme plugins
│   └── custom/               # Your custom plugin category
│       └── your-plugin.lua
└── util/
    └── your-util.lua         # Custom utility functions
```

### 🛠 Advanced Customization

**Custom utility functions:**
```lua
-- lua/util/my-utils.lua
local M = {}

function M.my_function()
  -- Your custom logic
end

return M
```

**Custom commands:**
```lua
-- lua/autocmds.lua - add to the file
vim.api.nvim_create_user_command("MyCommand", function()
  require("util.my-utils").my_function()
end, { desc = "My custom command" })
```

**Environment-specific configuration:**
```lua
-- lua/config-local.lua (add to .gitignore)
-- Machine-specific settings that shouldn't be shared
return {
  -- Your local overrides
}
```

## Plugin Manager

This configuration uses [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager, which provides:

- Fast startup times with lazy loading
- Automatic plugin updates checking
- Clean plugin management interface
- Lockfile support for reproducible installations

## Key Mappings

### General Mappings

| Action                    | Mappings                 |
| ------------------------- | ------------------------ |
| Leader key                | Space                    |
| Local                        |
| Exit insert mode          | `jk`, `<C-c>`            |
| Find file                 | `<leader>f`              |
| Find buffer               | `<leader>b`              |
| Recent files              | `<leader>r`              |
| Search (live grep)        | `<leader>\`              |
| File explorer             | `<leader>E`              |
| No highlight              | `<leader>hn`             |

### Window Management

| Action                     | Mapping                |
| -------------------------- | ---------------------- |
| Split window horizontally  | `ss`, `<leader>ws`     |
| Split window vertically    | `sv`, `<leader>wv`     |
| Go to the up window        | `sk`, `<leader>wk`     |
| Go to the down window      | `sj`, `<leader>wj`     |
| Go to the left window      | `sh`, `<leader>wh`     |
| Go to the right window     | `sl`, `<leader>wl`     |
| Switch window              | `sw`, `<leader>ww`     |
| Increase height            | `s+`, `<leader>w+`     |
| Decrease height            | `s-`, `<leader>w-`     |
| Increase width             | `s>`, `<leader>w>`     |
| Decrease width             | `s<`, `<leader>w<`     |
| Equal size                 | `s=`, `<leader>w=`     |
| Max out width              | `s|`, `<leader>w|`     |
| Close current window       | `sc`, `<leader>wc`     |
| Close other windows        | `so`, `<leader>wo`     |

### Buffers

| Actions         | Mappings    |
| --------------- | ----------- |
| Switch buffers  | `<leader>b` |
| Next buffer     | `]b`        |
| Previous buffer | `[b`        |

### Search

| Action                  | Mapping        |
| ----------------------- | -------------- |
| Search buffer           | `<leader>ss`   |
| Search project          | `<leader>sp`   |
| Search buffer symbols   | `<leader>sm`   |
| Search workspace symbols| `<leader>sM`   |
| Search treesitter symbols | `<leader>st` |

### Code Actions

| Action              | Mapping                  |
| ------------------- | ------------------------ |
| Code action         | `<leader>ca`, `,a`       |
| Format              | `<leader>cf`, `,f`       |
| Rename              | `<leader>cr`, `,r`       |
| Goto definition     | `<leader>cg`, `,g`       |
| Type definition     | `<leader>ct`, `,t`       |
| Show references     | `<leader>ce`, `,e`       |
| Show implementations| `<leader>ci`, `,i`       |
| Buffer diagnostics  | `<leader>cd`, `,d`       |
| Workspace diagnostics| `<leader>cD`, `,D`      |
| Incoming calls      | `<leader>ci`, `,i`       |
| Outgoing calls      | `<leader>co`, `,o`       |
| Quickfix            | `<leader>cq`, `,q`       |
| Hover doc           | `<leader>ch`, `,h`       |
| Signature help      | `<leader>cH`, `,H`       |

### Debugging

| Action                | Mapping             |
| --------------------- | ------------------- |
| Toggle Breakpoint     | `<leader>db`        |
| Breakpoint Condition  | `<leader>dB`        |
| Run/Continue          | `<leader>dc`        |
| Run with Args         | `<leader>da`        |
| Run to Cursor         | `<leader>dC`        |
| Go to Line (No Exec)  | `<leader>dg`        |
| Step Into             | `<leader>di`        |
| Step Over             | `<leader>dO`        |
| Step Out              | `<leader>do`        |
| Down                  | `<leader>dj`        |
| Up                    | `<leader>dk`        |
| Run Last              | `<leader>dl`        |
| Pause                 | `<leader>dP`        |
| Toggle REPL           | `<leader>dr`        |
| Session               | `<leader>ds`        |
| Terminate             | `<leader>dt`        |
| Widgets               | `<leader>dw`        |

### Git

| Action                     | Mapping          |
| -------------------------- | ---------------- |
| Next hunk                  | `<leader>gj`     |
| Prev hunk                  | `<leader>gk`     |
| Blame line                 | `<leader>gl`     |
| Blame buffer               | `<leader>gL`     |
| Preview hunk               | `<leader>gp`     |
| Reset hunk                 | `<leader>gr`     |
| Reset buffer               | `<leader>gR`     |
| Stage hunk                 | `<leader>gs`     |
| Undo stage hunk            | `<leader>gu`     |
| List files                 | `<leader>gf`     |
| Status                     | `<leader>go`     |
| Branches                   | `<leader>gb`     |
| Buffer commits             | `<leader>gc`     |
| Project commits            | `<leader>gC`     |
| Diff                       | `<leader>gd`     |

### Toggle/Test

| Action                | Mapping            |
| --------------------- | ------------------ |
| Toggle AutoSave       | `<leader>ts`       |
| Test current method   | `<leader>tm`       |
| Debug current method  | `<leader>td`       |
| Test current file     | `<leader>tf`       |
| Toggle test summary   | `<leader>tS`       |
| Toggle test output    | `<leader>to`       |
| Show test diagnostic  | `<leader>td`       |
| Hide test diagnostic  | `<leader>tD`       |

### Help

| Action                | Mapping            |
| --------------------- | ------------------ |
| No highlight          | `<leader>hn`       |
| Help tags             | `<leader>hh`       |
| Man pages             | `<leader>hm`       |
| Todos                 | `<leader>ht`       |
| Keymaps               | `<leader>hm`       |
| Registers             | `<leader>hr`       |
| Jumps                 | `<leader>hj`       |
| Commands              | `<leader>hx`       |
| Commands history      | `<leader>hX`       |

### AI

| Action                | Mapping            |
| --------------------- | ------------------ |
| Inline                | `<leader>ap`       |
| Actions               | `<leader>aa`       |
| Chat                  | `<leader>ac`       |

### Session Management

| Action                         | Mapping        |
| ------------------------------ | -------------- |
| Save session                   | `<leader>qs`   |
| Load current session           | `<leader>q.`   |
| Load last session              | `<leader>ql`   |
| Update plugins                 | `<leader>qu`   |
| Save                           | `<leader>qw`   |
| Save all                       | `<leader>qW`   |
| Quit                           | `<leader>qq`   |
| Save and quit all              | `<leader>qQ`   |

### Navigation

| Action                      | Mapping                       |
| --------------------------- | ----------------------------- |
| Next todo                   | `]t`                          |
| Previous todo               | `[t`                          |
| Next diagnostic             | `]d`                          |
| Previous diagnostic         | `[d`                          |
| Next method start           | `]m`                          |
| Previous method start       | `[m`                          |
| Next method end             | `]M`                          |
| Previous method end         | `[M`                          |
| Next class start            | `]c`                          |
| Previous class start        | `[c`                          |
| Next class end              | `]C`                          |
| Previous class end          | `[C`                          |

## Development Workflow

### 🔄 Making Changes

1. **Enable Development Mode**:
   ```bash
   export NVIM_DEV=1
   export NVIM_LOG_LEVEL=DEBUG
   ```

2. **Edit Configuration Files**:
   - Modify files in `lua/` directory
   - Use `:DevReload` to apply changes instantly

3. **Test Changes**:
   ```vim
   :DevTest        " Run all tests
   :DevValidate    " Validate configurations
   ```

4. **Monitor Performance**:
   ```bash
   export NVIM_PROFILE=1
   ```
   ```vim
   :DevProfile     " Show performance impact
   ```

### 🐛 Debugging Issues

1. **Check System Information**:
   ```vim
   :DevInfo        " System details
   :DevPlugins     " Plugin status
   ```

2. **View Logs**:
   ```lua
   local logger = require("util.logger")
   logger.show_recent(20)  -- Show recent log entries
   ```

3. **Test Individual Components**:
   ```vim
   :DevReloadModule util.lsp    " Reload specific module
   :DevTest                     " Run targeted tests
   ```

### 📦 Adding New Features

1. **Create Module**:
   ```lua
   -- lua/util/my-feature.lua
   local logger = require("util.logger")
   local validate = require("util.validate")
   
   local M = {}
   
   function M.my_function(config)
     validate.assert(config, "table", "config")
     logger.debug("Executing my_function")
     
     -- Your implementation
     
     logger.info("Feature executed successfully")
   end
   
   return M
   ```

2. **Add Tests**:
   ```lua
   -- test/my_feature_test.lua
   local test = require("util.test")
   local my_feature = require("util.my-feature")
   
   test.describe("My Feature", function()
     test.it("should work correctly", function()
       local result = my_feature.my_function({})
       test.assert_not_nil(result)
     end)
   end)
   ```

3. **Validate and Test**:
   ```vim
   :DevReload      " Reload configuration
   :DevTest        " Run all tests
   :DevValidate    " Validate configurations
   ```

## Troubleshooting

### Common Issues

#### Slow Startup
```vim
:DevProfile     " Check startup time
:PerfReport     " Detailed performance analysis
```

**Solutions**:
- Review plugin loading with `:DevPlugins`
- Check lazy loading configuration
- Disable unnecessary plugins

#### Plugin Errors
```vim
:DevInfo        " System information
:DevPlugins     " Plugin status
```

**Solutions**:
- Check `:checkhealth` for missing dependencies
- Validate plugin configurations with `:DevValidate`
- Review error logs with `:messages`

#### Configuration Errors
```bash
# Enable debug logging
export NVIM_LOG_LEVEL=DEBUG
nvim
```

**Solutions**:
- Use `:DevTest` to identify specific issues
- Check validation errors with `:DevValidate`
- Review recent logs in development mode

#### Memory Issues
```vim
:PerfMemory 5 60    " Monitor memory for 60 seconds
```

**Solutions**:
- Check for memory leaks in custom code
- Review plugin memory usage
- Restart Neovim periodically for long sessions

### Getting Help

1. **Built-in Diagnostics**:
   ```vim
   :checkhealth    " Neovim health check
   :DevInfo        " Configuration diagnostics
   ```

2. **Log Analysis**:
   ```lua
   local logger = require("util.logger")
   logger.show_recent(50)  " Recent activity
   logger.get_recent(10)   " Programmatic access
   ```

3. **Performance Profiling**:
   ```vim
   :PerfReport     " Performance overview
   :DevProfile 30  " Memory monitoring
   ```

### Environment Setup

**Development Environment**:
```bash
# ~/.bashrc or ~/.zshrc
export NVIM_DEV=1
export NVIM_PROFILE=1
export NVIM_LOG_LEVEL=DEBUG
```

**Production Environment**:
```bash
# Minimal logging for better performance
export NVIM_LOG_LEVEL=WARN
# No development tools
unset NVIM_DEV
unset NVIM_PROFILE
```

## Contributing

### Code Standards

1. **Documentation**: All functions must have LuaDoc annotations
2. **Error Handling**: Use `logger.safe_call()` for risky operations
3. **Validation**: Validate inputs with `util.validate`
4. **Testing**: Write tests for new features
5. **Performance**: Profile new code with development tools

### Submitting Changes

1. **Test Thoroughly**:
   ```vim
   :DevTest        " All tests pass
   :DevValidate    " No configuration errors
   :DevProfile     " No performance regression
   ```

2. **Update Documentation**: Modify this README for user-facing changes

3. **Follow Commit Convention**: Use clear, descriptive commit messages

## License

This configuration is provided as-is for educational and personal use.
