-- Extra `[`/`]` targets, restricted to the suffixes this config leaves free.
--
-- mini.bracketed ships thirteen targets, and seven of them land on keys that
-- are already taken here: b/d/l/q/t/w/y belong to bufferline, diagnostics, the
-- location and quickfix lists, treesitter-context, window nav and yanky. Those
-- are switched off with `suffix = ""` rather than remapped, so nothing this
-- config already documents changes meaning -- only genuinely unused keys are
-- claimed.
--
-- What that leaves is the part worth having: `[x` for merge conflicts (the diff
-- workflow in lua/plugin/vcs/ has no conflict jump of its own) and `[i` for
-- indent blocks, plus jump-list, oldfile and undo-state motions.
--
-- `comment` is off as well, for a different reason: `[c`/`]c` is the
-- treesitter class jump (lua/plugin/ui/treesitter.lua) and, in diff mode, the
-- builtin "next change" -- both worth more than hopping between comments, and
-- this plugin loads late enough to have shadowed them.
return {
  "echasnovski/mini.bracketed",
  event = "BufReadPost",
  opts = {
    -- Kept: conflict, indent, jump, oldfile, undo.
    buffer     = { suffix = "" }, -- [b/]b -> bufferline
    comment    = { suffix = "" }, -- [c/]c -> treesitter class jump / diff change
    diagnostic = { suffix = "" }, -- [d/]d -> vim.diagnostic
    file       = { suffix = "" }, -- directory walking; pickers cover this
    location   = { suffix = "" }, -- [l/]l -> location list
    quickfix   = { suffix = "" }, -- [q/]q -> quickfix
    treesitter = { suffix = "" }, -- [t/]t -> todo-comments
    window     = { suffix = "" }, -- <C-h/j/k/l> owns window movement
    yank       = { suffix = "" }, -- [y/]y -> yanky history
  },
}
