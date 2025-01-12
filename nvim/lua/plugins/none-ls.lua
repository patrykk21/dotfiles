return {
  "nvimtools/none-ls.nvim",
  enabled = true,
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-lua/plenary.nvim",
    "semanticart/ruby-code-actions.nvim",
    "nvimtools/none-ls-extras.nvim",
  },
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local null_ls = require("null-ls")
    local ruby_code_actions = require("ruby-code-actions")

    null_ls.setup({
      debug = false,
      debounce = 150,
      save_after_format = false,
      sources = {
        require("none-ls.diagnostics.eslint_d").with({
          condition = function(utils)
            return utils.root_has_file({ ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json" })
          end,
        }),
        require("none-ls.code_actions.eslint_d").with({
          condition = function(utils)
            return utils.root_has_file({ ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json" })
          end,
        }),

        null_ls.builtins.code_actions.gitsigns,
        null_ls.builtins.diagnostics.rubocop,
        null_ls.builtins.formatting.prettierd,
        null_ls.builtins.formatting.rubocop,
        null_ls.builtins.formatting.stylua,

        ruby_code_actions.insert_frozen_string_literal,
        ruby_code_actions.autocorrect_with_rubocop,
      },
      root_dir = require("null-ls.utils").root_pattern("package.json", ".null-ls-root", "Gemfile", ".git"),
    })
  end,
}
