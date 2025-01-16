return {
  "mbbill/undotree",
  cmd = "UndotreeToggle",
  keys = {
    { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle UndoTree" },
  },
  config = function()
    vim.g.undotree_WindowLayout = 2 -- Change this to customize layout
    vim.g.undotree_SplitWidth = 30 -- Width of the undo tree window
    vim.g.undotree_DiffpanelHeight = 15 -- Height of the diff panel
    vim.g.undotree_SetFocusWhenToggle = 1 -- Focus undotree when toggled
  end,
}
