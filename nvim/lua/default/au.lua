local api = vim.api

-- Highlight when yanking
local yank_group = api.nvim_create_augroup('HighlightYank', { clear = true })
api.nvim_create_autocmd('TextYankPost', {
  command = "silent! lua vim.highlight.on_yank { higroup = 'IncSearch', timeout = 100 }" ,
  group = yank_group
})

