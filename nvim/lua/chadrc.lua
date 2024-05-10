local M = {}

vim.cmd("highlight St_relativepath guifg=#626a83 guibg=#2a2b36")

local stbufnr = function()
	return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
end

M.ui = {
	theme = "tokyodark",
	transparency = false,
	hl_override = {
		Visual = {
			-- fg = "sun",
		},
		FoldColumn = {
			fg = "grey",
			bg = "black",
		},
		-- DiffAdd, DiffDelete, DiffText, SignColumn
		DiffChange = {
			fg = "purple",
		},
	},
	cmp = {
		icons = true,
		lspkind_text = true,
		style = "atom",
	},
	statusline = {
		theme = "default",
		order = { "mode", "relativepath", "file", "git", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "cwd", "cursor" },
		modules = {
			relativepath = function()
				local path = vim.api.nvim_buf_get_name(stbufnr())

				if path == "" then
					return ""
				end

				return "%#St_relativepath#  " .. vim.fn.expand("%:.:h") .. " /"
			end,
		},
	},
}

return M
