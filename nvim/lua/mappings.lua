local map = vim.keymap.set

-- General
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map({ "n", "i", "v" }, "<C-s>", function()
	vim.cmd("w")
end)

-- NvChad/ui
map("n", "<leader>th", function()
	require("nvchad.themes").open({ style = "flat" })
end, { desc = "telescope nvchad themes" })

-- vim-illuminate
map("n", "[[", function()
	require("illuminate").goto_next_reference(false)
end, { desc = "Next Reference" })
map("n", "]]", function()
	require("illuminate").goto_prev_reference(false)
end, { desc = "Prev Reference" })

-- Buffer
map("n", "<leader>nb", "<cmd>enew<CR>", { desc = "New buffer" })

-- Diagnostics
map("n", "<leader>do", vim.diagnostic.open_float, { desc = "Lsp diagnostic open" })
map("n", "<leader>dk", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "<leader>dj", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })

-- Telescope
map("n", "<leader>saK", "<cmd>Telescope keymaps<cr>", { desc = "Telescope Find keymaps" })
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find files" })
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Telescope Find Files" })
map(
	"n",
	"<leader>fa",
	"<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
	{ desc = "telescope find all files" }
)
map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "Telescope Live Grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Telescope Find Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Telescope Help Page" })
map("n", "<leader>ma", "<cmd>Telescope marks<CR>", { desc = "Telescope Find Marks" })
map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Telescope Find Oldfiles" })
map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Telescope Find In Current Buffer" })
map("n", "<leader>cm", "<cmd>Telescope git_commits<CR>", { desc = "Telescope Git Commits" })
map("n", "<leader>gt", "<cmd>Telescope git_status<CR>", { desc = "Telescope Git Status" })
map("n", "<leader>pt", "<cmd>Telescope terms<CR>", { desc = "Telescope Pick Hidden Term" })
map("n", "::", ":Telescope cmdline<CR>", { noremap = true, desc = "Cmdline" })

--- whichkey
map("n", "<leader>sK", "<cmd>WhichKey <CR>", { desc = "Whichkey all keymaps" })
map("n", "<leader>sk", function()
	vim.cmd("WhichKey " .. vim.fn.input("WhichKey: "))
end, { desc = "Whichkey query lookup" })

-- Nvim-tree
map("n", "<leader>e", "<cmd>NvimTreeFindFile<CR>", { desc = "Open nvim tree to current file" })
map("n", "<c-n>", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle nvim tree" })

-- Ufo
map("n", "zR", require("ufo").openAllFolds)
map("n", "zM", require("ufo").closeAllFolds)
map("n", "zr", require("ufo").openFoldsExceptKinds)
map("n", "zm", require("ufo").closeFoldsWith)
map("n", "zk", function()
	local winid = require("ufo").peekFoldedLinesUnderCursor()
	if not winid then
		vim.lsp.buf.hover()
	end
end)

-- LSP
map("n", "<leader>fm", vim.lsp.buf.format, { desc = "File Format" })

-- Function to check if nvim-tree is open and focus it
local function focus_nvim_tree()
	local tree_api = require("nvim-tree.api")
	if tree_api.tree.is_visible() then
		tree_api.tree.focus()
		return true
	end
	return false
end

-- Move between splits or focus nvim-tree
map("n", "<C-h>", function()
	if not pcall(vim.cmd, "wincmd h") then
		if not focus_nvim_tree() then
			print("No more splits on the left!")
		end
	end
end, { desc = "Move left or focus nvim-tree" })

map("n", "<C-j>", "<C-w>j", { desc = "Move down" })
map("n", "<C-k>", "<C-w>k", { desc = "Move up" })
map("n", "<C-l>", "<C-w>l", { desc = "Move right" })
