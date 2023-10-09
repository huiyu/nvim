local M = {}

M.keybind_consumers = {}

Keybind = {}

function Keybind:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Keybind:has_cmd()
  return self.cmd ~= nil
end

function M.register_keybind_consumer(keybind_consumer)
  M.keybind_consumers[#M.keybind_consumers + 1] = keybind_consumer
end

local function extend_tbl(defaults, opts)
  opts = opts or {}
  return defaults and vim.tbl_deep_extend("force", defaults, opts) or opts
end

--- Table based API for setting keybindings
--- @param map_table table: table of keybindings,
---    the first key is the vim mode
---    the second key is the key to map
---    the value is the function to set the mapping to
--- @param base_opts? table: A base set of options to set on every keybindings
local function set_mappings(map_table, base_opts)
  for mode, keymaps in pairs(map_table) do
    -- iterate over the first keys for each mode
    for key, value in pairs(keymaps) do
      -- build the options for the command accordingly
      -- 2 types of value:
      --    mode: n
      --    key: <leader>w
      --    value: 2 type of value: { "<cmd>w<cr>", desc = "Save" } or "<cmd>w<cr>"
      if value then
        local cmd = value
        local opts = base_opts
        if type(value) == "table" then
          cmd = value[1]
          opts = extend_tbl(opts, value)
          opts[1] = nil
        end

        local keybind = Keybind:new({
          mode = mode,
          key = key,
          cmd = cmd,
          opts = opts,
        })

        for _, consumer in ipairs(M.keybind_consumers) do
          consumer(keybind)
        end
      end
    end
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = function()
    set_mappings(require("mappings"), {})
  end,
})

return M
