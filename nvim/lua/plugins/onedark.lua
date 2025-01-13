return {
  "navarasu/onedark.nvim",
  lazy = false,
  priority = 1000,
  enabled = false,
  config = function()
    require("onedark").setup({
      style = "darker", -- Options: "dark", "darker", "cool", "deep", "warm", "warmer", "light"
      colors = {
        bg_darker = "#1e222a", -- Define a custom darker background color
        bg_highlight = "#2c323c", -- Define a custom highlight background color
      },
      highlights = {
        TelescopeNormal = { bg = "$bg_darker", fg = "$fg" },
        TelescopeBorder = { bg = "$bg_darker", fg = "$bg_darker" },
        TelescopePromptNormal = { bg = "$bg_highlight", fg = "$fg" },
        TelescopePromptBorder = { bg = "$bg_highlight", fg = "$bg_highlight" },
        TelescopePromptTitle = { bg = "$bg_highlight", fg = "$green" },
        TelescopePreviewTitle = { bg = "$bg_darker", fg = "$blue" },
        TelescopeResultsTitle = { bg = "$bg_darker", fg = "$bg_darker" },
      },
    })
    require("onedark").load()
  end,
}
