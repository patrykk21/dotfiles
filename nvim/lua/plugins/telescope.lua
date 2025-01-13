return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-lua/plenary.nvim",
	},
	cmd = "Telescope",
	opts = function()
		return {
			defaults = {
				vimgrep_arguments = {
					"rg",
					"-L",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
				},
				prompt_prefix = "   ",
				selection_caret = "  ",
				entry_prefix = "  ",
				initial_mode = "insert",
				selection_strategy = "reset",
				sorting_strategy = "ascending",
				layout_strategy = "horizontal",
				layout_config = {
					horizontal = {
						prompt_position = "top",
						preview_width = 0.55,
						results_width = 0.8,
					},
					width = 0.87,
					height = 0.80,
					preview_cutoff = 120,
				},
				file_sorter = require("telescope.sorters").get_fuzzy_file,
				file_ignore_patterns = { "node_modules" },
				generic_sorter = require("telescope.sorters").get_generic_fuzzy_sorter,
				path_display = { "truncate" },
				winblend = 0,
				border = true,
				borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
				color_devicons = true,
				set_env = { ["COLORTERM"] = "truecolor" },
				file_previewer = require("telescope.previewers").vim_buffer_cat.new,
				grep_previewer = require("telescope.previewers").vim_buffer_vimgrep.new,
				qflist_previewer = require("telescope.previewers").vim_buffer_qflist.new,
				buffer_previewer_maker = require("telescope.previewers").buffer_previewer_maker,
				mappings = {
					n = {
						["q"] = require("telescope.actions").close,
						["<ESC>"] = require("telescope.actions").close,
					},
				},
			},
			pickers = {
				oldfiles = {
					cwd_only = true,
				},
			},
			extensions_list = { "themes", "terms" }, -- Added extensions
		}
	end,
	config = function(_, opts)
		local telescope = require("telescope")
		telescope.setup(opts)

		-- Load extensions
		for _, ext in ipairs(opts.extensions_list) do
			pcall(telescope.load_extension, ext)
		end
	end,
}
