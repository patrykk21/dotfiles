return {
	"rcarriga/nvim-notify",
	lazy = false,
	config = function(_, opts)
		require("notify").setup(opts)
		vim.notify = require("notify")
	end,
}
