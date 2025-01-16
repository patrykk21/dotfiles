return {
  "echasnovski/mini.nvim",
  event = "VeryLazy",
  version = "*",
  config = function()
    require("mini.ai").setup()
  end,
}
