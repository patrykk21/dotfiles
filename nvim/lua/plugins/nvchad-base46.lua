return {
	"nvchad/base46",
	-- Disable in VSCode - use VSCode themes  
	enabled = not vim.g.vscode,
	lazy = false,
	build = function()
		require("base46").load_all_highlights()
	end,
}
