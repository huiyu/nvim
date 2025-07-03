---@module "icons"
---Icon definitions for Neovim UI components
---
---Provides consistent icon sets for various plugins and UI elements.
---Uses Nerd Font symbols for better visual representation.
---
---@example
---local icons = require("icons")
---print(icons.diagnostics.Error)  -- " "
---print(icons.git.added)          -- " "

local M = {}

M.dap = {
  Stopped             = "󰁕",
  Breakpoint          = "",
  BreakpointCondition = "",
  BreakpointRejected  = "",
  LogPoint            = ".>",
}

M.diagnostics = {
  Error = " ",
  Warn  = " ",
  Hint  = " ",
  Info  = " ",
}

M.git = {
  added    = " ",
  modified = " ",
  removed  = " ",
}

M.kinds = {
  Array         = " ",
  Boolean       = "󰨙 ",
  Class         = " ",
  Codeium       = "󰘦 ",
  Color         = " ",
  Control       = " ",
  Collapsed     = " ",
  Constant      = "󰏿 ",
  Constructor   = " ",
  Copilot       = " ",
  Enum          = " ",
  EnumMember    = " ",
  Event         = " ",
  Field         = " ",
  File          = " ",
  Folder        = " ",
  Function      = "󰊕 ",
  Interface     = " ",
  Key           = " ",
  Keyword       = " ",
  Method        = "󰊕 ",
  Module        = " ",
  Namespace     = "󰦮 ",
  Null          = " ",
  Number        = "󰎠 ",
  Object        = " ",
  Operator      = " ",
  Package       = " ",
  Property      = " ",
  Reference     = " ",
  Snippet       = "󱄽 ",
  String        = " ",
  Struct        = "󰆼 ",
  Supermaven    = " ",
  TabNine       = "󰏚 ",
  Text          = " ",
  TypeParameter = " ",
  Unit          = " ",
  Value         = " ",
  Variable      = "󰀫 ",
}



return M;
