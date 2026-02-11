return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  config = function()
    require("smart-splits").setup({
      -- Tmux integration - allow seamless navigation with tmux panes
      at_edge = "stop",  -- Stop at edges instead of wrapping
      move_cursor_same_row = false,
      resize_mode = {
        silent = true,
        hooks = {
          on_enter = function()
            vim.notify("Entering resize mode")
          end,
          on_leave = function()
            vim.notify("Exiting resize mode")
          end,
        },
      },
      -- Tmux integration
      multiplexer_integration = "tmux",
    })
  end,
}
