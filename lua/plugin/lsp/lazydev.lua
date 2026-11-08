-- lazydev hands lua_ls the runtime plus the plugins a file requires. The repo's
-- .luarc.json must not set `workspace.library`: lua_ls lets that file override
-- the library a client sends, which silently dropped every plugin type here.
return {
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    -- Nvim 0.12 ships `vim.uv` annotations in $VIMRUNTIME/lua/uv/_meta.lua,
    -- which lazydev already adds; LuaLS's bundled luv types are only needed
    -- on the 0.11 floor.
    library = vim.fn.has("nvim-0.12") == 0
        and { { path = "${3rd}/luv/library", words = { "vim%.uv" } } }
      or {},
  },
}
