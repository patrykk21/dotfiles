return {
	"lukas-reineke/indent-blankline.nvim",
	-- Disable in VSCode - VSCode has its own indent guides
	enabled = not vim.g.vscode,
	event = "User FilePost",
	opts = {
		indent = { char = "│", highlight = "IblChar" },
		scope = { char = "│", highlight = "IblScopeChar" },
	},
	config = function(_, opts)
		dofile(vim.g.base46_cache .. "blankline")

		local hooks = require("ibl.hooks")
		hooks.register(hooks.type.WHITESPACE, hooks.builtin.hide_first_space_indent_level)
		require("ibl").setup(opts)

		dofile(vim.g.base46_cache .. "blankline")
	end,
}
