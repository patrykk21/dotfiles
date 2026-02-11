return {
  "https://gitlab.com/HiPhish/rainbow-delimiters.nvim",
  -- Disable in VSCode - can be distracting with VSCode's own bracket features
  enabled = not vim.g.vscode,
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("rainbow-delimiters.setup")
  end,
}
