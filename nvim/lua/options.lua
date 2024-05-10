require("nvchad.options")

local opt = vim.opt
local o = vim.o
local g = vim.g
-- local wo = vim.wo

opt.number = true
opt.relativenumber = true
opt.swapfile = false

-- wo.foldmethod = 'expr'
-- wo.foldexpr = 'nvim_treesitter#foldexpr()'
-- wo.foldlevel = 20

o.foldcolumn = "1"
o.foldlevel = 99
o.foldlevelstart = 99
o.foldenable = true

opt.fillchars = {
  eob = " ",
  fold = " ",
  foldopen = "",
  foldsep = " ",
  foldclose = "",
}

g.editorconfig = true
