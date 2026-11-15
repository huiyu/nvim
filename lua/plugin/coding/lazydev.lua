-- lazydev hands lua_ls the runtime plus the plugins a file requires. The repo's
-- .luarc.json must not set `workspace.library`: lua_ls lets that file override
-- the library a client sends, which silently dropped every plugin type here.
return {
  "folke/lazydev.nvim",
  ft = "lua",
  -- No `${3rd}/luv/library` entry: Nvim 0.12 ships the `vim.uv` annotations
  -- in $VIMRUNTIME/lua/uv/_meta.lua, which lazydev already adds.
  opts = {},
}
