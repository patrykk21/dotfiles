return {
  "rcarriga/nvim-notify",
  lazy = false,
  config = function(_, opts)
    opts.background_colour = "#000000"

    require("notify").setup(opts)
    vim.notify = require("notify")
  end,
}
