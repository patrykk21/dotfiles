local nvim_lsp = require('lspconfig')
local servers = { 'solargraph' }

local on_attach = function(client, bufnr)
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  local opts = { buffer = 0, noremap = true, silent = true }
  vim.keymap.set('n', '<leader>dd', vim.diagnostic.open_float, opts)
  vim.keymap.set('n', '<leader>dn', vim.diagnostic.goto_next, opts)
  vim.keymap.set('n', '<leader>dp', vim.diagnostic.goto_prev, opts)
  -- vim.keymap.set('n', '<leader>dl', vim.diagnostic.setloclist, opts)

  local bufopts = { buffer = 0, noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set('n', '<leader>gD', vim.lsp.buf.declaration, bufopts)
  -- vim.keymap.set('n', '<leader>gd', vim.lsp.buf.definition, bufopts)
  -- vim.keymap.set('n', '<leader>gi', vim.lsp.buf.implementation, bufopts)
  -- vim.keymap.set('n', '<leader>gt', vim.lsp.buf.type_definition, bufopts)
  vim.keymap.set('n', '<leader>h', vim.lsp.buf.hover, bufopts)
  vim.keymap.set('n', '<leader>sh', vim.lsp.buf.signature_help, bufopts)
  -- vim.keymap.set('n', '<leader>ref', vim.lsp.buf.references, bufopts)
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
  vim.keymap.set('n', '<leader>r', vim.lsp.buf.rename, bufopts)
  vim.keymap.set('n', '<leader>ff', vim.lsp.buf.formatting, bufopts)
  vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, bufopts)
  vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
  vim.keymap.set('n', '<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, bufopts)
end

local lsp_flags = {
}

for _, lsp in ipairs(servers) do
  nvim_lsp[lsp].setup {
    on_attach = on_attach,
    flags = lsp_flags,
  }
end
