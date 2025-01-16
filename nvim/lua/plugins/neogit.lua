return {
  "NeogitOrg/neogit",
  lazy = "VeryLazy",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("neogit").setup({
      integrations = { diffview = true },
    })
  end,
}
