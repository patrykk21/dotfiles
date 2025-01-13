local icons = require("icons")

local options = {
	git = { enable = true },
	renderer = {
		highlight_opened_files = "all",
		highlight_git = true,
		icons = {
			glyphs = {
				default = icons.ui.Text,
				symlink = icons.ui.FileSymlink,
				bookmark = icons.ui.BookMark,
				folder = {
					arrow_closed = icons.ui.ChevronRight,
					arrow_open = icons.ui.ChevronShortDown,
					default = icons.ui.Folder,
					open = icons.ui.FolderOpen,
					empty = icons.ui.EmptyFolder,
					empty_open = icons.ui.EmptyFolderOpen,
					symlink = icons.ui.FolderSymlink,
					symlink_open = icons.ui.FolderOpen,
				},
			},
			show = {
				git = false,
			},
		},
	},
	filters = {
		dotfiles = false,
		git_ignored = false,
	},
}

return {
	"nvim-tree/nvim-tree.lua",
	cmd = { "NvimTreeToggle", "NvimTreeFocus" },
	config = function()
		dofile(vim.g.base46_cache .. "nvimtree")

		require("nvim-tree").setup(options)
	end,
}
