-- Set leader key early
vim.g.mapleader = " "

-- Load settings, plugins, and mappings
require("settings")
require("lazy-startup")
require("autocmds")

vim.schedule(function()
  require("mappings")
end)
