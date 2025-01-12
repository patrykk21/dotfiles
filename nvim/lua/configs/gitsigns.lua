local options = {
  signs = {
    add = { text = "│" },
    change = { text = "│" },
    delete = { text = "󰍵" },
    topdelete = { text = "‾" },
    changedelete = { text = "~" },
    untracked = { text = "│" },
  },

  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns

    local function opts(desc)
      return { buffer = bufnr, desc = desc }
    end

    local map = vim.keymap.set

    -- Actions
    map("n", "<leader>hs", gs.stage_hunk, opts("Stage Hunk"))
    map("n", "<leader>hr", gs.reset_hunk, opts("Reset Hunk"))
    map("v", "<leader>hs", function()
      gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, opts("Stage Hunk"))
    map("v", "<leader>hr", function()
      gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, opts("Reset Hunk"))
    map("n", "<leader>hS", gs.stage_buffer, opts("Stage Buffer"))
    map("n", "<leader>hu", gs.undo_stage_hunk, opts("Undo Stage Hunk"))
    map("n", "<leader>hR", gs.reset_buffer, opts("Reset Buffer"))
    map("n", "<leader>hp", gs.preview_hunk, opts("Preview Hunk"))
    map("n", "<leader>hb", function()
      gs.blame_line({ full = true })
    end, opts("Blame Line"))
    map("n", "<leader>tb", gs.toggle_current_line_blame, opts("Toggle Current Line Blame"))
    map("n", "<leader>hd", gs.diffthis, opts("Diff This"))
    map("n", "<leader>hD", function()
      gs.diffthis("~")
    end, opts("Diff This"))
    map("n", "<leader>td", gs.toggle_deleted, opts("Toggle Deleted"))

    -- Text object
    map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>")

    -- Close preview with ESC
    map("n", "<ESC>", function()
      local something_closed = false

      for _, id in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(id).relative ~= "" then
          vim.api.nvim_win_close(id, false)

          something_closed = true
        end
      end

      -- Clear search by pressing ESC
      if not something_closed then
        vim.cmd("noh")
      end
    end, { buffer = bufnr })
  end,
}

return options
