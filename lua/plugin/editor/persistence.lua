return {
	"folke/persistence.nvim",
	event = "BufReadPre",
	opts = {
		save_empty = false, -- don't save if there are no open file buffers
	},
}
