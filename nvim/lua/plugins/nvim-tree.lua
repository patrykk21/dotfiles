local cfg = require("configs.nvim-tree")

return {
  "nvim-tree/nvim-tree.lua",
  opts = function()
    return cfg.opts
  end,
  config = function(_, opts)
    dofile(vim.g.base46_cache .. "nvimtree")
    require("nvim-tree").setup(opts)

    -- TODO: Fix colors!!!
    -- vim.cmd("hi! link GitSignsChangedelete GitSignsDelete")
    -- vim.cmd("hi! link NvimTreeGitNew GitSignsAdd")
    -- vim.cmd("hi! link NvimTreeGitDirty GitSignsChange")
  end,
}
