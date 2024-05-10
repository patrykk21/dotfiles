return {
  "kevinhwang91/nvim-ufo",
  dependencies = {
    "kevinhwang91/promise-async",
    "luukvbaal/statuscol.nvim",
  },
  config = function()
    local statuscolCfg = require("configs.statuscol")
    local ufoCfg = require("configs.ufo")

    require("statuscol").setup(statuscolCfg)
    require("ufo").setup(ufoCfg)
  end,
}
