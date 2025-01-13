dofile(vim.g.base46_cache .. "mason")

local cfg = {
  PATH = "skip",

  ui = {
    icons = {
      package_pending = " ",
      package_installed = " ",
      package_uninstalled = " ",
    },
  },

  max_concurrent_installers = 10,
}

return {
  "williamboman/mason.nvim",
  cmd = { "Mason", "MasonInstall", "MasonInstallAll", "MasonUpdate" },
  opts = function()
    return cfg
  end,
  config = function(_, opts)
    dofile(vim.g.base46_cache .. "mason")
    require("mason").setup(opts)

    -- custom nvchad cmd to install all mason binaries listed
    vim.api.nvim_create_user_command("MasonInstallAll", function()
      if opts.ensure_installed and #opts.ensure_installed > 0 then
        vim.cmd("MasonInstall " .. table.concat(opts.ensure_installed, " "))
      end
    end, {})

    vim.g.mason_binaries_list = opts.ensure_installed
  end,
}
