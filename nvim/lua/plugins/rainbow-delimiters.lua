return {
  "https://gitlab.com/HiPhish/rainbow-delimiters.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("rainbow-delimiters.setup")
  end,
}
