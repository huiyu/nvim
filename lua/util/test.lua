---@module "util.test"
---Lightweight testing framework for Neovim configuration
---
---Provides a simple testing framework for validating configuration
---components, utility functions, and plugin integrations.
---
---@example
---local test = require("util.test")
---
---test.describe("String utilities", function()
---  test.it("should detect string endings", function()
---    test.assert_true("hello.lua":ends_with(".lua"))
---    test.assert_false("hello.txt":ends_with(".lua"))
---  end)
---end)

local logger = require("util.logger")

local M = {}

-- Test state
local current_suite = nil
local test_stats = {
  suites = 0,
  tests = 0,
  passed = 0,
  failed = 0,
  errors = {},
}

-- Test output configuration
local config = {
  verbose = false,
  show_stack_trace = true,
  auto_run = true,
}

---Set test configuration options
---@param opts table Configuration options
function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  logger.debug("Test framework configured: %s", vim.inspect(config))
end

---Reset test statistics
function M.reset_stats()
  test_stats = {
    suites = 0,
    tests = 0,
    passed = 0,
    failed = 0,
    errors = {},
  }
end

---Get current test statistics
---@return table stats Test statistics
function M.get_stats()
  return vim.deepcopy(test_stats)
end

---Print test results with color coding
---@param message string Message to print
---@param level? string Log level for coloring (info, warn, error)
local function print_result(message, level)
  if level == "error" then
    vim.api.nvim_echo({{ "✗ " .. message, "ErrorMsg" }}, true, {})
  elseif level == "warn" then
    vim.api.nvim_echo({{ "⚠ " .. message, "WarningMsg" }}, true, {})
  else
    vim.api.nvim_echo({{ "✓ " .. message, "DiagnosticOk" }}, true, {})
  end
end

---Describe a test suite
---@param name string Suite name
---@param fn function Function containing tests
function M.describe(name, fn)
  if type(name) ~= "string" then
    error("Test suite name must be a string", 2)
  end
  
  if type(fn) ~= "function" then
    error("Test suite function must be a function", 2)
  end
  
  current_suite = name
  test_stats.suites = test_stats.suites + 1
  
  if config.verbose then
    print(string.format("\nDescribing: %s", name))
    print(string.rep("-", 40))
  end
  
  logger.debug("Starting test suite: %s", name)
  
  local success, error_msg = pcall(fn)
  
  if not success then
    local err = string.format("Test suite '%s' failed to run: %s", name, error_msg)
    table.insert(test_stats.errors, err)
    print_result(err, "error")
    logger.error("Test suite error: %s", err)
  end
  
  current_suite = nil
end

---Define a test case
---@param name string Test case name
---@param fn function Test function
function M.it(name, fn)
  if type(name) ~= "string" then
    error("Test name must be a string", 2)
  end
  
  if type(fn) ~= "function" then
    error("Test function must be a function", 2)
  end
  
  test_stats.tests = test_stats.tests + 1
  local full_name = current_suite and string.format("%s: %s", current_suite, name) or name
  
  logger.debug("Running test: %s", full_name)
  
  local success, error_msg = pcall(fn)
  
  if success then
    test_stats.passed = test_stats.passed + 1
    if config.verbose then
      print_result(string.format("  %s", name), "info")
    end
    logger.debug("Test passed: %s", full_name)
  else
    test_stats.failed = test_stats.failed + 1
    local err = string.format("Test '%s' failed: %s", full_name, error_msg)
    table.insert(test_stats.errors, err)
    
    print_result(string.format("  %s", name), "error")
    if config.show_stack_trace then
      print(string.format("    Error: %s", error_msg))
    end
    
    logger.error("Test failed: %s", err)
  end
end

---Skip a test (placeholder for future implementation)
---@param name string Test name
---@param _fn function Test function (ignored)
function M.xit(name, _fn)
  if config.verbose then
    vim.api.nvim_echo({{ "⊘ " .. string.format("  %s (skipped)", name), "Comment" }}, true, {})
  end
end

-- Assertion functions

---Assert that a condition is true
---@param condition any Condition to test
---@param message? string Custom error message
function M.assert_true(condition, message)
  if not condition then
    error(message or string.format("Expected true, got %s", tostring(condition)), 2)
  end
end

---Assert that a condition is false
---@param condition any Condition to test
---@param message? string Custom error message
function M.assert_false(condition, message)
  if condition then
    error(message or string.format("Expected false, got %s", tostring(condition)), 2)
  end
end

---Assert that two values are equal
---@param actual any Actual value
---@param expected any Expected value
---@param message? string Custom error message
function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("Expected %s, got %s", 
                                   vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

---Assert that two values are not equal
---@param actual any Actual value
---@param not_expected any Value that should not match
---@param message? string Custom error message
function M.assert_not_equal(actual, not_expected, message)
  if actual == not_expected then
    error(message or string.format("Expected %s to not equal %s", 
                                   vim.inspect(actual), vim.inspect(not_expected)), 2)
  end
end

---Assert that a value is nil
---@param value any Value to test
---@param message? string Custom error message
function M.assert_nil(value, message)
  if value ~= nil then
    error(message or string.format("Expected nil, got %s", vim.inspect(value)), 2)
  end
end

---Assert that a value is not nil
---@param value any Value to test
---@param message? string Custom error message
function M.assert_not_nil(value, message)
  if value == nil then
    error(message or "Expected non-nil value", 2)
  end
end

---Assert that a value has a specific type
---@param value any Value to test
---@param expected_type string Expected type name
---@param message? string Custom error message
function M.assert_type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(message or string.format("Expected type %s, got %s", expected_type, actual_type), 2)
  end
end

---Assert that a function throws an error
---@param fn function Function that should throw
---@param expected_error? string Expected error message pattern
---@param message? string Custom error message
function M.assert_error(fn, expected_error, message)
  if type(fn) ~= "function" then
    error("assert_error expects a function", 2)
  end
  
  local success, error_msg = pcall(fn)
  
  if success then
    error(message or "Expected function to throw an error", 2)
  end
  
  if expected_error and not string.match(error_msg, expected_error) then
    error(message or string.format("Expected error matching '%s', got '%s'", 
                                   expected_error, error_msg), 2)
  end
end

---Assert that two tables have the same structure and values
---@param actual table Actual table
---@param expected table Expected table
---@param message? string Custom error message
function M.assert_table_equal(actual, expected, message)
  if type(actual) ~= "table" or type(expected) ~= "table" then
    error("assert_table_equal expects two tables", 2)
  end
  
  local function compare_tables(t1, t2)
    for k, v in pairs(t1) do
      if type(v) == "table" and type(t2[k]) == "table" then
        if not compare_tables(v, t2[k]) then
          return false
        end
      elseif v ~= t2[k] then
        return false
      end
    end
    
    for k, _ in pairs(t2) do
      if t1[k] == nil then
        return false
      end
    end
    
    return true
  end
  
  if not compare_tables(actual, expected) then
    error(message or string.format("Tables not equal:\nActual: %s\nExpected: %s", 
                                   vim.inspect(actual), vim.inspect(expected)), 2)
  end
end

---Run all tests and display results
function M.run()
  print("\n" .. string.rep("=", 50))
  print("TEST RESULTS")
  print(string.rep("=", 50))
  
  print(string.format("Suites: %d", test_stats.suites))
  print(string.format("Tests:  %d", test_stats.tests))
  print(string.format("Passed: %d", test_stats.passed))
  print(string.format("Failed: %d", test_stats.failed))
  
  if test_stats.failed > 0 then
    print("\nFAILURES:")
    print(string.rep("-", 30))
    for _, error_msg in ipairs(test_stats.errors) do
      print_result(error_msg, "error")
    end
  end
  
  local success_rate = test_stats.tests > 0 and 
                      (test_stats.passed / test_stats.tests * 100) or 0
  
  print(string.format("\nSuccess Rate: %.1f%%", success_rate))
  
  if test_stats.failed == 0 then
    print_result("All tests passed!", "info")
  else
    print_result(string.format("%d test(s) failed", test_stats.failed), "error")
  end
  
  logger.info("Test run completed: %d/%d passed", test_stats.passed, test_stats.tests)
  
  return test_stats.failed == 0
end

-- Auto-run tests if requested
if config.auto_run then
  vim.api.nvim_create_user_command("TestRun", function()
    M.run()
  end, { desc = "Run all tests" })
  
  vim.api.nvim_create_user_command("TestReset", function()
    M.reset_stats()
    print("Test statistics reset")
  end, { desc = "Reset test statistics" })
end

return M