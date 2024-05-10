local M = {}
local icons = require("icons")

M.opts = {
	git = { enable = true },
	renderer = {
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
    git_ignored = false
  }
}

return M
