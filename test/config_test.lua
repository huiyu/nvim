---@module "test.config_test"
---Configuration validation tests
---
---Tests to ensure the Neovim configuration loads correctly
---and all components are properly configured.

local test = require("util.test")
local validate = require("util.validate")
local logger = require("util.logger")

-- Configure test framework
test.setup({
  verbose = true,
  show_stack_trace = true,
})

test.describe("Configuration Validation", function()
  
  test.it("should load all core modules", function()
    local modules = {
      "util.logger",
      "util.validate", 
      "util.test",
      "util.performance",
      "util.string-ext",
      "util.lsp",
      "util.common",
      "util.file",
      "util.window",
    }
    
    for _, module_name in ipairs(modules) do
      local ok, module = pcall(require, module_name)
      test.assert_true(ok, string.format("Failed to load module: %s", module_name))
      test.assert_type(module, "table", string.format("Module %s should return a table", module_name))
    end
  end)
  
  test.it("should have valid plugin specifications", function()
    -- Test a few key plugin files
    local plugin_files = {
      "plugin.lsp.lsp",
      "plugin.ui.solarized", 
      "plugin.editor.telescope",
      "lang.java",
    }
    
    for _, plugin_file in ipairs(plugin_files) do
      local ok, spec = pcall(require, plugin_file)
      if ok and type(spec) == "table" then
        for _, plugin_spec in ipairs(spec) do
          if type(plugin_spec) == "table" then
            local valid, errors = validate.plugin_spec(plugin_spec)
            test.assert_true(valid, string.format("Invalid plugin spec in %s: %s", 
                                                 plugin_file, table.concat(errors, ", ")))
          end
        end
      end
    end
  end)
  
  test.it("should have valid key mappings", function()
    local ok, mappings = pcall(require, "mappings")
    test.assert_true(ok, "Failed to load mappings")
    test.assert_type(mappings, "table", "Mappings should be a table")
    
    -- Validate mapping structure
    for i, mapping in ipairs(mappings) do
      test.assert_type(mapping, "table", string.format("Mapping %d should be a table", i))
      test.assert_type(mapping[1], "string", string.format("Mapping %d should have string key", i))
      
      -- Check for required desc field
      if not mapping.desc then
        logger.warn("Mapping %s missing description", mapping[1])
      end
    end
  end)
  
  test.it("should have valid options configuration", function()
    local ok = pcall(require, "options")
    test.assert_true(ok, "Failed to load options")
    
    -- Test some critical options
    test.assert_equal(vim.opt.number:get(), true, "Line numbers should be enabled")
    test.assert_equal(vim.opt.relativenumber:get(), true, "Relative numbers should be enabled")
    test.assert_equal(vim.opt.expandtab:get(), true, "Expand tab should be enabled")
  end)
  
end)

test.describe("Utility Functions", function()
  
  test.it("should extend string functions", function()
    require("util.string-ext")
    
    test.assert_true(string.starts_with("hello.lua", "hello"))
    test.assert_false(string.starts_with("hello.lua", "world"))
    test.assert_true(string.ends_with("hello.lua", ".lua"))
    test.assert_false(string.ends_with("hello.lua", ".txt"))
    
    test.assert_equal(string.trim("  hello  "), "hello")
    test.assert_table_equal(string.split("a,b,c", ","), {"a", "b", "c"})
  end)
  
  test.it("should validate configurations correctly", function()
    local schema = {
      name = "string",
      count = "number", 
      enabled = "boolean",
      optional_field = { type = "string", optional = true },
    }
    
    local valid_config = {
      name = "test",
      count = 42,
      enabled = true,
    }
    
    local valid, errors = validate.config(valid_config, schema)
    test.assert_true(valid, string.format("Valid config should pass: %s", table.concat(errors, ", ")))
    
    local invalid_config = {
      name = 123,  -- Wrong type
      count = "not a number",  -- Wrong type
      enabled = true,
    }
    
    valid, errors = validate.config(invalid_config, schema)
    test.assert_false(valid, "Invalid config should fail")
    test.assert_true(#errors > 0, "Should have validation errors")
  end)
  
  test.it("should handle table operations", function()
    local common = require("util.common")
    
    local tbl = common.table({a = 1, b = 2, c = 3})
    local keys = tbl:keys():get()
    
    test.assert_equal(#keys, 3, "Should have 3 keys")
    test.assert_true(tbl:containsKey("a"), "Should contain key 'a'")
    test.assert_true(tbl:containsValue(2), "Should contain value 2")
    test.assert_false(tbl:containsValue(99), "Should not contain value 99")
  end)
  
end)

test.describe("Logger Functionality", function()
  
  test.it("should log messages at different levels", function()
    -- Test basic logging (this will output to notifications)
    logger.debug("Test debug message")
    logger.info("Test info message") 
    logger.warn("Test warning message")
    logger.error("Test error message")
    
    -- Test log level management
    local original_level = logger.get_level()
    logger.set_level("ERROR")
    test.assert_equal(logger.get_level(), "ERROR")
    
    logger.set_level(original_level)  -- Restore
    test.assert_equal(logger.get_level(), original_level)
  end)
  
  test.it("should handle safe function calls", function()
    local success, result = logger.safe_call(function()
      return 42
    end, "test operation")
    
    test.assert_true(success, "Safe call should succeed")
    test.assert_equal(result, 42, "Should return function result")
    
    success, result = logger.safe_call(function()
      error("test error")
    end, "failing operation")
    
    test.assert_false(success, "Safe call should catch errors")
    test.assert_type(result, "string", "Should return error message")
  end)
  
end)

-- Run the tests
test.run()