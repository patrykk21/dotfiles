local function setup()
  local lspconfig = require("lspconfig")
  local cmp_lsp = require("cmp_nvim_lsp")
  local configs = {}
  -- local conf = require("nvconfig").ui.lsp

  local map = vim.keymap.set

  configs.on_init = function(client, _)
    if client.supports_method("textDocument/semanticTokens") then
      client.server_capabilities.semanticTokensProvider = nil
    end
  end

  local on_attach = function(client, bufnr)
    local function opts(desc)
      return { buffer = bufnr, desc = "LSP " .. desc }
    end

    map("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))
    map("n", "gd", vim.lsp.buf.definition, opts("Go to definition"))
    map("n", "K", vim.lsp.buf.hover, opts("hover information"))
    map("n", "gi", vim.lsp.buf.implementation, opts("Go to implementation"))
    map("n", "<leader>sh", vim.lsp.buf.signature_help, opts("Show signature help"))
    -- map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts("Add workspace folder"))
    -- map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts("Remove workspace folder"))
    --
    -- map("n", "<leader>wl", function()
    -- 	print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    -- end, opts("List workspace folders"))

    map("n", "<leader>D", vim.lsp.buf.type_definition, opts("Go to type definition"))

    map("n", "<leader>ra", function()
      require("nvchad.lsp.renamer")()
    end, opts("NvRenamer"))

    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
    map("n", "gr", vim.lsp.buf.references, opts("Show references"))

    -- setup signature popup
    -- if conf.signature and client.server_capabilities.signatureHelpProvider then
    --   require("nvchad.lsp.signature").setup(client, bufnr)
    -- end
  end

  local on_init = configs.on_init
  local capabilities = cmp_lsp.default_capabilities()

  capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true,
  }

  local servers = {
    "ts_ls",
    "tailwindcss",
    "gopls",
    -- "eslint",
  }

  for _, lsp in ipairs(servers) do
    lspconfig[lsp].setup({
      on_init = on_init,
      on_attach = on_attach,
      capabilities = capabilities,
    })
  end

  lspconfig.lua_ls.setup({
    on_init = on_init,
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { library = { vim.env.VIMRUNTIME } },
        format = {
          enable = true,
          defaultConfig = {
            align_continuous_assign_statement = false,
            align_continuous_rect_table_field = false,
            align_array_table = false,
          },
        },
      },
    },
  })

  lspconfig.solargraph.setup({
    on_init = on_init,
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
      solargraph = {
        formatting = false,
        diagnostic = false,
      },
    },
    root_dir = lspconfig.util.root_pattern(".null-ls-root", "Gemfile", ".git", ".ruby-version"),
  })

  lspconfig.pyright.setup({
    on_init = on_init,
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
      python = {
        pythonPath = "./venv/bin/python",
      },
    },
  })
end

return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
  },
  config = function()
    dofile(vim.g.base46_cache .. "syntax")
    dofile(vim.g.base46_cache .. "treesitter")

    setup()
    require("ufo").setup()
  end,
  opts = {
    format_notify = true,
  },
}
