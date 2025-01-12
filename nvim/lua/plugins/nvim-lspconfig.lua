return {
  "neovim/nvim-lspconfig",
  dependencies = { "williamboman/mason-lspconfig.nvim" },
  config = function()
    dofile(vim.g.base46_cache .. "syntax")
    dofile(vim.g.base46_cache .. "treesitter")

    require("nvchad.configs.lspconfig").defaults()
    require("configs.lspconfig")
    require("ufo").setup()

  end,
  opts = {
    format_notify = true,
  },
}
