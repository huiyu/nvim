-- The refactors are operators (expr maps returning `g@`): in Visual mode they
-- act on the selection, in Normal mode they wait for a motion or text object
-- (`,ef_`, `,efj`, `,exi(`). Extract Block is gone upstream; `,ef` over the
-- block's lines replaces it.
local function op(name)
  return function() return require("refactoring")[name]() end
end

return {
  "ThePrimeagen/refactoring.nvim",
  -- Upstream requires Nvim 0.12.5 (vim.pos, vim.range); that requirement is
  -- the config's floor, checked by lua/config/health.lua.
  dependencies = {
    {
      "lewis6991/async.nvim",
      -- Nvim 0.12 has no vim.async, so refactoring.nvim falls back to
      -- `require("async")` -- a name promise-async (nvim-ufo's dependency)
      -- also claims with an unrelated API. ufo loads on BufReadPost and wins
      -- package.loaded, after which every refactor fails on `async.wrap`.
      -- vim.async is the slot refactoring.nvim reads first and Nvim 0.13 fills
      -- natively; loading async.nvim by path keeps ufo's `async` untouched.
      config = function(plugin)
        if vim.async == nil then vim.async = dofile(plugin.dir .. "/lua/async.lua") end
      end,
    },
  },
  cmd = "Refactor",
  keys = {
    { ",ef", op("extract_func"),         desc = "Extract function…",         mode = { "n", "x" }, expr = true },
    { ",eF", op("extract_func_to_file"), desc = "Extract function to file…", mode = { "n", "x" }, expr = true },
    { ",ex", op("extract_var"),          desc = "Extract variable…",         mode = { "n", "x" }, expr = true },
    { ",i",  op("inline_var"),           desc = "Inline variable",           mode = { "n", "x" }, expr = true },
    { ",R", function() require("refactoring").select_refactor() end, desc = "Select refactor…", mode = { "n", "x" } },
  },
  opts = {},
}
