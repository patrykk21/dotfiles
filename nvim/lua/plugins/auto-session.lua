return {
  "rmagatti/auto-session",
  lazy = false,
  enabled = false,
  config = function()
    require("auto-session").setup({
      log_level = "error",
      auto_session_suppress_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
    })
  end,
}
