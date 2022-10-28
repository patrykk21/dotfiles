require("tokyonight").setup({
  transparent = true,
  styles = {
    sidebars = "transparent",
    floats = "transparent"
  },
  on_highlights = function(hl, colors)
    hl.LineNr = {
      fg = colors.yellow
    }
    hl.CursorLineNr = {
      fg = colors.orange
    }
  end
})

vim.cmd("colorscheme tokyonight")
