require("nvchad.mappings")

local map = vim.keymap.set
local del = vim.keymap.del

map("n", "<leader>fm", vim.lsp.buf.format, { desc = "File Format" })

-- Remove default keybinds from NvChad
del("n", "<tab>")
del("n", "<S-tab>")
del("n", "<leader>x")
del("n", "<leader>n")
del("n", "<leader>rn")
del("n", "<leader>b")
del("n", "<leader>wK")
del("n", "<leader>wk")
del("n", "<leader>h")
del("n", "<leader>v")

-- Custom keybinds section

-- buffer
map("n", "<leader>nb", "<cmd>enew<CR>", { desc = "New buffer" })

-- tabufline
map({ "n", "i" }, "<C-Right>", function()
	require("nvchad.tabufline").next()
end, { desc = "Buffer Goto next" })
map({ "n", "i" }, "<C-Left>", function()
	require("nvchad.tabufline").prev()
end, { desc = "Buffer Goto prev" })
map("n", "<leader>w", function()
	require("nvchad.tabufline").close_buffer()
end, { desc = "Buffer Close" })

--- diagnostic
map("n", "<leader>do", vim.diagnostic.open_float, { desc = "Lsp diagnostic open" })
map("n", "<leader>dk", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "<leader>dj", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })

--- whichkey
map("n", "<leader>sK", "<cmd>WhichKey <CR>", { desc = "Whichkey all keymaps" })
map("n", "<leader>sk", function()
	vim.cmd("WhichKey " .. vim.fn.input("WhichKey: "))
end, { desc = "Whichkey query lookup" })

--- Telescope
map("n", "<leader>saK", "<cmd>Telescope keymaps<cr>", { desc = "Telescope Find keymaps" })
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find files" })
map(
	"n",
	"<C-P>",
	"<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
	{ desc = "Telescope Find all files" }
)
map("n", "::", ":Telescope cmdline<CR>", { noremap = true, desc = "Cmdline" })

--- Ufo
map("n", "zR", require("ufo").openAllFolds)
map("n", "zM", require("ufo").closeAllFolds)
map("n", "zr", require("ufo").openFoldsExceptKinds)
map("n", "zm", require("ufo").closeFoldsWith) -- closeAllFolds == closeFoldsWith(0)
map("n", "zk", function()
	local winid = require("ufo").peekFoldedLinesUnderCursor()
	if not winid then
		vim.lsp.buf.hover()
	end
end)
