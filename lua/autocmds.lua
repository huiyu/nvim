local cmd = vim.api.nvim_create_user_command

local function custom_telescope_opts(custom_opts)
  custom_opts = custom_opts or {}
  local opts
  if custom_opts.theme == nil then
    opts = {}
  elseif custom_opts.theme == "dropdown" then
    opts = require("telescope.themes").get_dropdown({
      layout_config = {
        prompt_position = "top",
        width = 0.9,
      },
      path_display = { "truncate" },
    })
  elseif custom_opts.theme == "ivy" then
    opts = require("telescope.themes").get_ivy({
      path_display = { "truncate" },
    })
  elseif custom_opts.theme == "cursor" then
    opts = require("telescope.themes").get_cursor({
      layout_config = {
        width = 0.9,
        height = 0.5,
      },
      path_display = { "truncate" },
    })
  end

  custom_opts["theme"] = nil

  return vim.tbl_deep_extend("force", opts, custom_opts)
end

-- File Commands
cmd(
  "ExploreCurrentDirectory",
  -- "Telescope file_browser path=%:p:h select_buffer=true",
  function()
    local opts = custom_telescope_opts {
      theme = "dropdown",
      path = "%:p:h",
      select_buffer = true,
    }
    require("telescope").extensions.file_browser.file_browser(opts)
  end,
  { desc = "Explore current directory" }
)
cmd("ExploreWorkingDirectory",
  function()
    local opts = custom_telescope_opts {
      theme = "dropdown",
    }
    require("telescope").extensions.file_browser.file_browser(opts)
  end,
  { desc = "Explore workspace directory" })

cmd("FindFiles", function(opts)
  -- merge opts with default
  require("telescope.builtin").find_files(
    vim.tbl_deep_extend("force", custom_telescope_opts {
      theme = "dropdown",
      cwd_only = true,
      hidden = false,
    }, opts)
  )
end, {
  desc = "Find files",
  nargs = "?",
})

cmd("FindRecentFiles", function()
  local opts = custom_telescope_opts {
    theme = "dropdown",
    cwd_only = true,
    hidden = true,
  }
  require("telescope.builtin").oldfiles(opts)
end, { desc = "Find recent files" })

cmd("FindBuffers", function()
  local opts = custom_telescope_opts {
    theme = "dropdown",
    cwd_only = true,
    hidden = true,
  }
  require("telescope.builtin").buffers(opts)
end, { desc = "Find buffers" })

cmd("HelpTags", function()
  require("telescope.builtin").help_tags()
end, { desc = "Help tags" })

cmd("ManPages", function()
  require("telescope.buitin").man_pages()
end, { desc = "Man Pages" })

-- Search commands
cmd("SearchBuffer",
  function()
    local opts = custom_telescope_opts {
      theme = "dropdown",
      cwd_only = true,
      search_dirs = { "%;p" },
    }
    require("telescope.builtin").live_grep(opts)
  end,
  { desc = "Search buffer" })

cmd("SearchWord", function()
  local opts = custom_telescope_opts {
    theme = "dropdown",
    cwd_only = true,
  }
  require("telescope.builtin").live_grep(opts)
end, { desc = "Search word" })

cmd("SearchWordUnderCursor", function()
  local opts = custom_telescope_opts {
    theme = "dropdown",
    cwd_only = true,
    path_display = { "truncate" },
  }
  require("telescope.builtin").grep_string(opts)
end, { desc = "Search word under cursor" })


--- Window
cmd("WindowCloseOthers", function()
  require("util.window").close_others()
end, { desc = "Close other windows" })

cmd("WindowCloseCurrent", function()
  require("util.window").close_current()
end, { desc = "Close current window" })

-- Plugin commands
cmd("PluginStatus", function()
  require("lazy").home()
end, { desc = "Plugin status" })

cmd("PluginInstall", function()
  require("lazy").install()
end, { desc = "Plugin install" })

cmd("PluginSync", function()
  require("lazy").sync()
end, { desc = "Plugin status" })

cmd("PluginUpdate", function()
  require("lazy").update()
end, { desc = "Plugin status" })

cmd("PluginCheck", function()
  require("lazy").check()
end, { desc = "Plugin check updates" })

cmd("PluginUpdateAll", function()
  require("lazy").sync({ wait = true })
  vim.cmd("MasonUpdate")
end, { desc = "Update plugins and packages" })

-- Lsp commands
cmd("LspRename", function()
  vim.lsp.buf.rename()
end, { desc = "Lsp rename" })

cmd("LspCodeAction", function()
  vim.lsp.buf.code_action()
end, { desc = "Lsp code action" })

cmd("LspFormatCode", function()
  vim.lsp.buf.format()
end, { desc = "Lsp format code" })

cmd("LspDefinitions", function()
  require("telescope.builtin").lsp_definitions(
    custom_telescope_opts {
      theme = "cursor"
    })
end, { desc = "Lsp definitions" })

cmd("LspTypeDefinitions", function()
  require("telescope.builtin").lsp_type_definitions(
    custom_telescope_opts {
      theme = "cursor"
    })
end, { desc = "Lsp type definitions" })


cmd("LspReferences",
  function()
    require("telescope.builtin").lsp_references(
      custom_telescope_opts {
        theme = "cursor"
      })
  end,
  { desc = "Lsp references" })

cmd("LspImplementations",
  function()
    require("telescope.builtin").lsp_implementations(
      custom_telescope_opts {
        theme = "cursor"
      })
  end,
  { desc = "Lsp implementations" })

cmd("LspIncomingCalls",
  function()
    require("telescope.builtin").lsp_incoming_calls(
      custom_telescope_opts {
        theme = "cursor"
      })
  end,
  { desc = "Lsp incoming calls" })

cmd("LspOutgoingCalls", function()
    require("telescope.builtin").lsp_outgoing_calls(
      custom_telescope_opts {
        theme = "cursor"
      })
  end,
  { desc = "Lsp outgoing calls" })


cmd("LspBufferDiagnostics",
  function()
    require("telescope.builtin").diagnostics(
      custom_telescope_opts {
        theme = "dropdown",
        bufnr = 0,
      })
  end,
  { desc = "Lsp buffer diagnostics" })


cmd("LspWorkspaceDiagnostics",
  function()
    require("telescope.builtin").diagnostics(
      custom_telescope_opts {
        theme = "dropdown",
      })
  end, { desc = "Lsp workspace diagnostics" })

cmd("LspNextDiagnostic",
  function()
    vim.diagnostic.goto_next()
  end, { desc = "Lsp next diagnostic" })

cmd("LspPrevDiagnostic",
  function()
    vim.diagnostic.goto_prev()
  end,
  { desc = "Lsp prev diagnostic" })

cmd("LspQuickfix",
  function()
    require("telescope.builtin").quickfix(
      custom_telescope_opts {
        theme = "cursor",
      })
  end,
  { desc = "Lsp quickfix" })

cmd("LspSignatureHelp",
  function()
    vim.lsp.buf.signature_help()
  end,
  { desc = "Lsp signature help" })

cmd("LspHoverDoc", function()
  vim.lsp.buf.hover()
end, { desc = "Lsp hover doc" })

cmd("LspWorkspaceSymbols", function()
  require("telescope.builtin").lsp_workspace_symbols(
    custom_telescope_opts {
      theme = "dropdown"
    })
end, { desc = "Lsp workspace symbols" })

cmd("LspBufferSymbols", function()
  require("telescope.builtin").lsp_document_symbols(
    custom_telescope_opts {
      theme = "dropdown"
    })
end, { desc = "Lsp buffer symbols" })

-- Session
cmd("SessionLoadLast", function()
  require("persistence").load({ last = true })
end, { desc = "Load last session" })

cmd("SessionLoadCurrent", function()
  require("persistence").load()
end, { desc = "Load current session" })

cmd("SessionSave", function()
  require("persistence").save()
end, { desc = "Save session" })
