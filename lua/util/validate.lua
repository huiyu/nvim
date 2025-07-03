---@module "util.validate"
---Configuration validation utilities with schema support
---
---Provides comprehensive validation for plugin configurations, user options,
---and runtime parameters to ensure type safety and prevent errors.
---
---@example
---local validate = require("util.validate")
---local schema = { name = "string", count = "number", enabled = "boolean" }
---validate.config({ name = "test", count = 5, enabled = true }, schema)

local logger = require("util.logger")

local M = {}

-- Built-in type validators
local type_validators = {
  string = function(value) return type(value) == "string" end,
  number = function(value) return type(value) == "number" end,
  boolean = function(value) return type(value) == "boolean" end,
  table = function(value) return type(value) == "table" end,
  ["function"] = function(value) return type(value) == "function" end,
  userdata = function(value) return type(value) == "userdata" end,
  thread = function(value) return type(value) == "thread" end,
  ["nil"] = function(value) return value == nil end,
}

-- Extended type validators
local extended_validators = {
  positive_number = function(value)
    return type(value) == "number" and value > 0
  end,
  
  non_negative_number = function(value)
    return type(value) == "number" and value >= 0
  end,
  
  non_empty_string = function(value)
    return type(value) == "string" and value ~= ""
  end,
  
  array = function(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for i, _ in pairs(value) do
      count = count + 1
      if type(i) ~= "number" or i ~= count then
        return false
      end
    end
    return true
  end,
  
  callable = function(value)
    return type(value) == "function" or 
           (type(value) == "table" and getmetatable(value) and getmetatable(value).__call)
  end,
  
  file_path = function(value)
    return type(value) == "string" and value ~= "" and not value:match("%.%.")
  end,
  
  buffer_number = function(value)
    return type(value) == "number" and value >= 0 and vim.api.nvim_buf_is_valid(value)
  end,
  
  window_number = function(value)
    return type(value) == "number" and value > 0 and vim.api.nvim_win_is_valid(value)
  end,
}

-- Combine all validators
local all_validators = vim.tbl_extend("force", type_validators, extended_validators)

---Validate a single value against a type specification
---@param value any The value to validate
---@param type_spec string|table Type specification (string or table with additional rules)
---@param field_name? string Name of the field for error messages
---@return boolean valid True if validation passes
---@return string? error_message Error message if validation fails
local function validate_value(value, type_spec, field_name)
  field_name = field_name or "value"
  
  -- Handle simple string type specs
  if type(type_spec) == "string" then
    local validator = all_validators[type_spec]
    if not validator then
      return false, string.format("Unknown type: %s", type_spec)
    end
    
    if not validator(value) then
      return false, string.format("%s must be of type %s, got %s", field_name, type_spec, type(value))
    end
    
    return true
  end
  
  -- Handle complex table type specs
  if type(type_spec) == "table" then
    local spec_type = type_spec.type or type_spec[1]
    
    -- Validate base type first
    if spec_type then
      local valid, err = validate_value(value, spec_type, field_name)
      if not valid then
        return false, err
      end
    end
    
    -- Check optional flag
    if type_spec.optional and value == nil then
      return true
    end
    
    -- Check custom validator
    if type_spec.validator and type(type_spec.validator) == "function" then
      local valid, err = type_spec.validator(value)
      if not valid then
        return false, err or string.format("%s failed custom validation", field_name)
      end
    end
    
    -- Check value constraints
    if type_spec.min and type(value) == "number" and value < type_spec.min then
      return false, string.format("%s must be >= %s, got %s", field_name, type_spec.min, value)
    end
    
    if type_spec.max and type(value) == "number" and value > type_spec.max then
      return false, string.format("%s must be <= %s, got %s", field_name, type_spec.max, value)
    end
    
    if type_spec.min_length and type(value) == "string" and #value < type_spec.min_length then
      return false, string.format("%s must be at least %d characters", field_name, type_spec.min_length)
    end
    
    if type_spec.max_length and type(value) == "string" and #value > type_spec.max_length then
      return false, string.format("%s must be at most %d characters", field_name, type_spec.max_length)
    end
    
    -- Check enum values
    if type_spec.values then
      local found = false
      for _, allowed in ipairs(type_spec.values) do
        if value == allowed then
          found = true
          break
        end
      end
      if not found then
        return false, string.format("%s must be one of: %s", field_name, table.concat(type_spec.values, ", "))
      end
    end
    
    return true
  end
  
  return false, string.format("Invalid type specification for %s", field_name)
end

---Validate configuration against a schema
---@param config table Configuration to validate
---@param schema table Schema defining expected structure and types
---@param strict? boolean If true, reject unknown fields (default: false)
---@return boolean valid True if validation passes
---@return table errors Array of error messages
function M.config(config, schema, strict)
  if type(config) ~= "table" then
    logger.error("Configuration must be a table, got %s", type(config))
    return false, {"Configuration must be a table"}
  end
  
  if type(schema) ~= "table" then
    logger.error("Schema must be a table, got %s", type(schema))
    return false, {"Schema must be a table"}
  end
  
  local errors = {}
  
  -- Validate required fields
  for field, type_spec in pairs(schema) do
    local value = config[field]
    local valid, err = validate_value(value, type_spec, field)
    
    if not valid then
      table.insert(errors, err)
      logger.debug("Validation error for field %s: %s", field, err)
    end
  end
  
  -- Check for unknown fields in strict mode
  if strict then
    for field, _ in pairs(config) do
      if not schema[field] then
        local err = string.format("Unknown field: %s", field)
        table.insert(errors, err)
        logger.debug("Strict validation error: %s", err)
      end
    end
  end
  
  local is_valid = #errors == 0
  
  if is_valid then
    logger.debug("Configuration validation passed")
  else
    logger.warn("Configuration validation failed with %d errors", #errors)
  end
  
  return is_valid, errors
end

---Validate function arguments
---@param args table Arguments to validate (usually {...})
---@param schema table Schema for argument validation
---@return boolean valid True if validation passes
---@return string? error_message Error message if validation fails
function M.args(args, schema)
  for i, type_spec in ipairs(schema) do
    local value = args[i]
    local valid, err = validate_value(value, type_spec, string.format("argument %d", i))
    
    if not valid then
      logger.debug("Argument validation failed: %s", err)
      return false, err
    end
  end
  
  return true
end

---Create a validator function for repeated use
---@param schema table Schema to validate against
---@param strict? boolean Strict mode for configuration validation
---@return function validator Validator function that takes config and returns (valid, errors)
function M.create_validator(schema, strict)
  return function(config)
    return M.config(config, schema, strict)
  end
end

---Validate plugin specification for lazy.nvim
---@param spec table Plugin specification
---@return boolean valid True if specification is valid
---@return table errors Array of error messages
function M.plugin_spec(spec)
  local schema = {
    [1] = { type = "string", min_length = 1 },  -- Plugin name/URL
    lazy = { type = "boolean", optional = true },
    enabled = { type = "boolean", optional = true },
    cond = { type = "function", optional = true },
    dependencies = { type = "table", optional = true },
    init = { type = "function", optional = true },
    config = { type = "function", optional = true },
    opts = { optional = true },  -- Can be any type
    cmd = { optional = true },   -- String or array
    ft = { optional = true },    -- String or array
    keys = { optional = true },  -- String, table or array
    event = { optional = true }, -- String or array
    priority = { type = "number", optional = true, min = 0, max = 1000 },
    version = { optional = true }, -- String or boolean
  }
  
  return M.config(spec, schema, false)
end

---Assert that a value is valid, throwing an error if not
---@param value any Value to validate
---@param type_spec string|table Type specification
---@param field_name? string Field name for error messages
function M.assert(value, type_spec, field_name)
  local valid, err = validate_value(value, type_spec, field_name)
  if not valid then
    error(err, 2)
  end
end

---Get available validator types
---@return table types Array of available type names
function M.get_types()
  local types = {}
  for type_name, _ in pairs(all_validators) do
    table.insert(types, type_name)
  end
  table.sort(types)
  return types
end

---Register a custom validator
---@param name string Validator name
---@param validator function Validator function that returns boolean
function M.register_validator(name, validator)
  if type(name) ~= "string" or name == "" then
    error("Validator name must be a non-empty string", 2)
  end
  
  if type(validator) ~= "function" then
    error("Validator must be a function", 2)
  end
  
  if all_validators[name] then
    logger.warn("Overriding existing validator: %s", name)
  end
  
  all_validators[name] = validator
  logger.debug("Registered custom validator: %s", name)
end

return M