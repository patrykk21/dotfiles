return {
	"nvchad/ui",
	-- Disable in VSCode - use VSCode UI
	enabled = not vim.g.vscode,
	dependencies = {
		"nvchad/base46",
	},
	lazy = false,
	config = function()
		require("nvchad")
	end,
}
