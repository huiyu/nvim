local treesitter = require("nvim-treesitter.configs")

treesitter.setup({
	ensure_installed = {
		"json",
		"html",
		"css",
		"vim",
		"lua",
		"javascript",
		"typescript",
		"tsx",
		"java",
		"kotlin",
		"ruby",
		"vue",
		"c",
		"c_sharp",
		"bash",
		"haskell",
	},
	highlight = {
		enable = true,
	},
	indent = {
		enable = true,
	},
	textobjects = {

		select = {
			enable = true,

			-- Automatically jump forward to textobj, similar to targets.vim
			lookahead = true,

			keymaps = {
				["af"] = { query = "@function.outer", desc = "Select outer part of a function region" },
				["if"] = { query = "@function.inner", desc = "Select inner part of a function region" },
				["ac"] = { query = "@class.outer", desc = "Select outer part of a class regionj" },
				["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
			},

			-- You can choose the select mode (default is charwise 'v')
			--
			-- Can also be a function which gets passed a table with the keys
			-- * query_string: eg '@function.inner'
			-- * method: eg 'v' or 'o'
			-- and should return the mode ('v', 'V', or '<c-v>') or a table
			-- mapping query_strings to modes.
			selection_modes = {
				["@parameter.outer"] = "v", -- charwise
				["@function.outer"] = "V", -- linewise
				["@class.outer"] = "<c-v>", -- blockwise
			},
			-- If you set this to `true` (default is `false`) then any textobject is
			-- extended to include preceding or succeeding whitespace. Succeeding
			-- whitespace has priority in order to act similarly to eg the built-in
			-- `ap`.
			--
			-- Can also be a function which gets passed a table with the keys
			-- * query_string: eg '@function.inner'
			-- * selection_mode: eg 'v'
			-- and should return true of false
			include_surrounding_whitespace = true,
		},

		-- Define mappings to swap the node uner the cursor with next or previous one, like function parameters or arguments
		swap = {
			enable = true,
		},

		-- Define own mapping to jump to the next or previous text object.
		move = {
			enable = true,
			set_jumps = true, -- whether to set jumps in the jumplist
		},
	},
})

local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.tsx.filetype_to_parsername = { "javascript", "javascript.tsx" }
