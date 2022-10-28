-- Consider the following plugins
-- https://github.com/pwntester/octo.nvim
-- https://github.com/nvim-telescope/telescope-project.nvim
-- https://github.com/nvim-telescope/telescope-github.nvim
-- https://github.com/nvim-telescope/telescope-symbols.nvim
-- https://github.com/gbrlsnchs/telescope-lsp-handlers.nvim
-- https://github.com/nvim-telescope/telescope-file-browser.nvim


-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'
  use 'folke/tokyonight.nvim'
  use 'neovim/nvim-lspconfig'
  
  -- Telescope
  use 'nvim-lua/plenary.nvim'
  use {
  'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate'
  }
  use 'nvim-telescope/telescope.nvim'
  use { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }

  -- Easy table creation in markdown
  use 'dhruvasagar/vim-table-mode'
  -- Highlight word under cursor
  use 'RRethy/vim-illuminate'
  -- Show animation on where you scrolled
  use 'gen740/SmoothCursor.nvim'
end)
