return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  config = function()
    require("smart-splits").setup({
      resize_mode = {
        silent = true,
      },
    })
  end,
}
