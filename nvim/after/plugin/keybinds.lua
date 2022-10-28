local nnoremap = require("keymap").nnoremap
local inoremap = require("keymap").inoremap
local xnoremap = require("keymap").xnoremap
local vnoremap = require("keymap").vnoremap

-- \x55 = Command
-- \x58 = Alt

-- Default
nnoremap("<leader>ex", "<cmd>Ex<CR>")
nnoremap("<CHAR-0x55>s", "<cmd>w<CR>")
nnoremap("<CHAR-0x55>S", "<cmd>wq<CR>")

-- LSP
-- Keybinds found in nvim/plugin/lsp.lua

-- Telescope
-- LSP overrides
nnoremap("<leader>ref", "<cmd>Telescope lsp_references<cr>")
nnoremap("<leader>sy", "<cmd>Telescope lsp_document_symbols<cr>")
nnoremap("<leader>dl", "<cmd>Telescope diagnostics<cr>")
nnoremap("<leader>gi", "<cmd>Telescope lsp_implementations<cr>")
nnoremap("<leader>gd", "<cmd>Telescope lsp_definitions<cr>")
nnoremap("<leader>gt", "<cmd>Telescope lsp_type_definitions<cr>")

-- General
nnoremap("<leader>fs", "<cmd>Telescope find_files<cr>")
nnoremap("<leader>fS", "<cmd>Telescope live_grep<cr>")
nnoremap("<leader>fw", "<cmd>Telescope current_buffer_fuzzy_find<cr>")
nnoremap("<leader>fb", "<cmd>Telescope buffers<cr>")
nnoremap("<leader>fh", "<cmd>Telescope help_tags<cr>")
nnoremap("<leader>fq", "<cmd>Telescope quickfix<cr>")
nnoremap("<leader>fc", "<cmd>Telescope commands<cr>")
nnoremap("<leader>fr", "<cmd>Telescope registers<cr>")
nnoremap("<leader>sY", "<cmd>Telescope treesitter<cr>")
