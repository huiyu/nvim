-- Editor-core parsers wanted everywhere, independent of which language modules
-- load. Language-specific parsers are OWNED by the matching `lua/lang/*.lua`
-- (contributed via `opts.ensure_installed` and merged in below), so this list is
-- deliberately limited to parsers that no language module declares — single
-- source of truth, mirroring how mason-lspconfig derives servers from lang/.
local ensure_installed = {
  "diff",
  "lua",
  "luadoc",
  "luap",
  "markdown",
  "markdown_inline",
  "printf",
  "query",
  "regex",
  "toml",
  "vim",
  "vimdoc",
  "xml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- `main` is the rewrite this spec is written for; `master` stays frozen
    -- for Nvim 0.11. main supports only the latest Nvim stable and has raised
    -- its minimum before (0.11 -> 0.12), so compare its README requirement
    -- with the floor in lua/config/health.lua when an update lands.
    branch = "main",
    -- The rewritten 'main' branch does not support lazy-loading.
    lazy = false,
    build = ":TSUpdate",
    -- `opts` lists are replaced (not merged) by lazy unless extended here, so
    -- parsers contributed by lang/*.lua accumulate instead of clobbering.
    opts_extend = { "ensure_installed" },
    config = function(_, opts)
      local nts = require("nvim-treesitter")
      nts.setup({
        install_dir = vim.fn.stdpath("data") .. "/site",
      })

      -- Merge the baseline list with parsers contributed by language modules
      -- (lang/*.lua add them through `opts.ensure_installed`), de-duplicating
      -- so a parser listed in both places is only requested once.
      local want, seen = {}, {}
      for _, list in ipairs({ ensure_installed, opts.ensure_installed or {} }) do
        for _, p in ipairs(list) do
          if not seen[p] then
            seen[p] = true
            table.insert(want, p)
          end
        end
      end

      -- Install any missing parsers from the desired list (async).
      local installed = {}
      for _, p in ipairs(nts.get_installed("parsers") or {}) do
        installed[p] = true
      end
      local missing = {}
      for _, p in ipairs(want) do
        if not installed[p] then
          table.insert(missing, p)
        end
      end
      if #missing > 0 then
        -- First launch (or after extending the list): block once so highlight is
        -- ready when the first buffer opens. Subsequent starts skip this path.
        nts.install(missing):wait(300000)
      end

      local function buf_lang(buf)
        local ft = vim.bo[buf].filetype
        return vim.treesitter.language.get_lang(ft) or ft
      end

      local function attach(buf, lang)
        pcall(vim.treesitter.start, buf, lang)
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        -- Folding is owned by ufo (see plugin/ui/ufo.lua); no foldexpr here.
      end

      -- `get_available()` reads a static table, so build the set once.
      -- `requested` keeps a failed or still-running install from being
      -- retried on every FileType of that language.
      local available, requested = nil, {}

      -- Enable highlight + indent + fold for buffers whose parser is available.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
        callback = function(args)
          local buf = args.buf
          local lang = buf_lang(buf)
          if not lang or lang == "" then
            return
          end

          -- Since Nvim 0.11 a missing parser is reported through the return
          -- value (nil, err) rather than raised, so pcall's status alone is
          -- always true -- that is what kept the install below from running.
          local ok, added = pcall(vim.treesitter.language.add, lang)
          if not ok then
            -- The parser file exists but does not load (truncated build,
            -- wrong ABI). A non-forced install counts it as installed and
            -- does nothing, so point at the forced rebuild instead.
            vim.notify_once(
              ("treesitter: the %s parser does not load; rebuild it with :TSInstall! %s\n%s"):format(lang, lang, added),
              vim.log.levels.WARN
            )
            return
          end
          if added then
            attach(buf, lang)
            return
          end

          -- Auto-install on demand if the parser is supported but missing
          -- (this replaces the old `auto_install = true` option).
          if requested[lang] then
            return
          end
          if not available then
            available = {}
            for _, p in ipairs(nts.get_available()) do
              available[p] = true
            end
          end
          if not available[lang] then
            return
          end
          requested[lang] = true

          -- FileType has already fired for every buffer waiting on this
          -- parser, so attach them here once it is built.
          nts.install({ lang }):await(vim.schedule_wrap(function(err, success)
            local load_ok, loaded = pcall(vim.treesitter.language.add, lang)
            if err or not success or not (load_ok and loaded) then
              return
            end
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_loaded(b) and buf_lang(b) == lang then
                attach(b, lang)
              end
            end
          end))
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = "VeryLazy",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          -- Automatically jump forward to textobj, similar to targets.vim
          lookahead = true,
          selection_modes = {
            ["@parameter.outer"] = "v", -- charwise
            ["@function.outer"] = "V",  -- linewise
            ["@class.outer"] = "<c-v>", -- blockwise
          },
          -- Extend the textobject to include surrounding whitespace
          -- (succeeding whitespace has priority, mirroring built-in `ap`).
          include_surrounding_whitespace = true,
        },
        move = {
          set_jumps = true, -- whether to set jumps in the jumplist
        },
      })

      local select = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")

      -- Select mappings (visual + operator-pending).
      local select_maps = {
        ["af"] = { "@function.outer", "Select outer part of a function region" },
        ["if"] = { "@function.inner", "Select inner part of a function region" },
        ["ac"] = { "@class.outer", "Select outer part of a class region" },
        ["ic"] = { "@class.inner", "Select inner part of a class region" },
      }
      for lhs, spec in pairs(select_maps) do
        vim.keymap.set({ "x", "o" }, lhs, function()
          select.select_textobject(spec[1], "textobjects")
        end, { desc = spec[2] })
      end

      -- In diff mode, fall back to built-in `]c`/`[c` (diff-hunk jumps)
      -- instead of jumping to the next/previous class textobject.
      local function diff_aware(fn, capture, lhs)
        return function()
          if vim.wo.diff and lhs:find("[%]%[]c") then
            vim.cmd("normal! " .. lhs)
            return
          end
          fn(capture, "textobjects")
        end
      end

      local move_maps = {
        { "]m", "@function.outer", move.goto_next_start },
        { "]c", "@class.outer",    move.goto_next_start },
        { "]M", "@function.outer", move.goto_next_end },
        { "]C", "@class.outer",    move.goto_next_end },
        { "[m", "@function.outer", move.goto_previous_start },
        { "[c", "@class.outer",    move.goto_previous_start },
        { "[M", "@function.outer", move.goto_previous_end },
        { "[C", "@class.outer",    move.goto_previous_end },
      }
      for _, m in ipairs(move_maps) do
        local lhs, capture, fn = m[1], m[2], m[3]
        vim.keymap.set(
          { "n", "x", "o" },
          lhs,
          diff_aware(fn, capture, lhs),
          { desc = capture }
        )
      end
    end,
  },
  {
    "windwp/nvim-ts-autotag",
    event = "VeryLazy",
    opts = {},
  },
}
