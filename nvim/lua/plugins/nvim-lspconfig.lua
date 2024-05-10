return {
  "neovim/nvim-lspconfig",
  dependencies = { "williamboman/mason-lspconfig.nvim" },
  config = function()
    require("nvchad.configs.lspconfig").defaults()
    require("configs.lspconfig")
    require("ufo").setup()
  end,
  opts = {
    format_notify = true,
  },
}
