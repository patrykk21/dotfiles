local map = vim.keymap.set

-- General
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map({ "n", "i", "v" }, "<C-s>", function()
  vim.cmd("w")
end)

-- NvChad/ui
map("n", "<leader>th", function()
  require("nvchad.themes").open({ style = "flat" })
end, { desc = "telescope nvchad themes" })

-- vim-illuminate
map("n", "[[", function()
  require("illuminate").goto_next_reference(false)
end, { desc = "Next Reference" })
map("n", "]]", function()
  require("illuminate").goto_prev_reference(false)
end, { desc = "Prev Reference" })

-- Buffer
local function reopenBuffer()
  local closed_buffers = vim.g.closed_buffers or {}
  local last_buf = table.remove(closed_buffers)
  vim.g.closed_buffers = closed_buffers -- Reassign the modified table back to vim.g

  if last_buf and vim.fn.filereadable(last_buf) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(last_buf))
  else
    print("No recently closed buffer to reopen.")
  end
end
map("n", "<leader>nb", "<cmd>enew<CR>", { desc = "New buffer" })
map("n", "<leader>w", "<cmd>bd<CR>", { desc = "Close buffer" })
map("n", "<C-S-t>", reopenBuffer, { desc = "Reopen buffer" })

-- Telescope
map("n", "<leader>saK", "<cmd>Telescope keymaps<cr>", { desc = "Telescope Find keymaps" })
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find files" })
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Telescope Find Files" })
map(
  "n",
  "<leader>fa",
  "<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
  { desc = "telescope find all files" }
)
map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "Telescope Live Grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Telescope Find Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Telescope Help Page" })
map("n", "<leader>ma", "<cmd>Telescope marks<CR>", { desc = "Telescope Find Marks" })
map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Telescope Find Oldfiles" })
map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Telescope Find In Current Buffer" })
map("n", "<leader>cm", "<cmd>Telescope git_commits<CR>", { desc = "Telescope Git Commits" })
map("n", "<leader>gt", "<cmd>Telescope git_status<CR>", { desc = "Telescope Git Status" })
map("n", "<leader>pt", "<cmd>Telescope terms<CR>", { desc = "Telescope Pick Hidden Term" })
map("n", "::", ":Telescope cmdline<CR>", { noremap = true, desc = "Cmdline" })

--- whichkey
map("n", "<leader>sK", "<cmd>WhichKey <CR>", { desc = "Whichkey all keymaps" })
map("n", "<leader>sk", function()
  vim.cmd("WhichKey " .. vim.fn.input("WhichKey: "))
end, { desc = "Whichkey query lookup" })

-- Nvim-tree
map("n", "<leader>e", "<cmd>NvimTreeFindFile<CR>", { desc = "Open nvim tree to current file" })
map("n", "<c-n>", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle nvim tree" })

-- Ufo
map("n", "zR", require("ufo").openAllFolds)
map("n", "zM", require("ufo").closeAllFolds)
map("n", "zr", require("ufo").openFoldsExceptKinds)
map("n", "zm", require("ufo").closeFoldsWith)
map("n", "zk", function()
  local winid = require("ufo").peekFoldedLinesUnderCursor()
  if not winid then
    vim.lsp.buf.hover()
  end
end)

-- LSP
map("n", "<leader>fm", vim.lsp.buf.format, { desc = "File Format" })

-- Move between splits or focus nvim-tree
map("n", "<A-h>", function()
  require("smart-splits").resize_left()
end, { desc = "Resize split left" })
map("n", "<A-j>", function()
  require("smart-splits").resize_down()
end, { desc = "Resize split down" })
map("n", "<A-k>", function()
  require("smart-splits").resize_up()
end, { desc = "Resize split up" })
map("n", "<A-l>", function()
  require("smart-splits").resize_right()
end, { desc = "Resize split right" })
map("n", "<C-h>", function()
  require("smart-splits").move_cursor_left()
end, { desc = "Move cursor left" })
map("n", "<C-j>", function()
  require("smart-splits").move_cursor_down()
end, { desc = "Move cursor down" })
map("n", "<C-k>", function()
  require("smart-splits").move_cursor_up()
end, { desc = "Move cursor up" })
map("n", "<C-l>", function()
  require("smart-splits").move_cursor_right()
end, { desc = "Move cursor right" })
map("n", "<C-\\>", function()
  require("smart-splits").move_cursor_previous()
end, { desc = "Move to previous cursor" })
map("n", "<leader><leader>h", function()
  require("smart-splits").swap_buf_left()
end, { desc = "Swap buffer left" })
map("n", "<leader><leader>j", function()
  require("smart-splits").swap_buf_down()
end, { desc = "Swap buffer down" })
map("n", "<leader><leader>k", function()
  require("smart-splits").swap_buf_up()
end, { desc = "Swap buffer up" })
map("n", "<leader><leader>l", function()
  require("smart-splits").swap_buf_right()
end, { desc = "Swap buffer right" })

-- harpoon
local harpoon = require("harpoon")
harpoon:setup({})
local conf = require("telescope.config").values
local function toggle_telescope(harpoon_files)
  local finder = function()
    local paths = {}
    for _, item in ipairs(harpoon_files.items) do
      table.insert(paths, item.value)
    end

    return require("telescope.finders").new_table({
      results = paths,
    })
  end

  require("telescope.pickers")
    .new({}, {
      prompt_title = "Harpoon",
      finder = finder(),
      previewer = conf.file_previewer({}),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, cmap)
        cmap({ "i", "n" }, "<C-d>", function()
          local state = require("telescope.actions.state")
          local selected_entry = state.get_selected_entry()
          local current_picker = state.get_current_picker(prompt_bufnr)

          table.remove(harpoon_files.items, selected_entry.index)
          current_picker:refresh(finder())
        end, { desc = "Remove entry from Harpoon list" })
        return true
      end,
    })
    :find()
end

map("n", "<C-S-a>", function()
  harpoon:list():add()
end, { desc = "Add current file to Harpoon list" })
map("n", "<C-S-e>", function()
  toggle_telescope(harpoon:list())
end, { desc = "Open Harpoon window using Telescope" })
map("n", "<C-S-h>", function()
  harpoon:list():select(1)
end, { desc = "Select first item in Harpoon list" })
map("n", "<C-S-j>", function()
  harpoon:list():select(2)
end, { desc = "Select second item in Harpoon list" })
map("n", "<C-S-k>", function()
  harpoon:list():select(3)
end, { desc = "Select third item in Harpoon list" })
map("n", "<C-S-l>", function()
  harpoon:list():select(4)
end, { desc = "Select fourth item in Harpoon list" })
map("n", "<C-S-p>", function()
  harpoon:list():prev()
end, { desc = "Navigate to previous item in Harpoon list" })
map("n", "<C-S-n>", function()
  harpoon:list():next()
end, { desc = "Navigate to next item in Harpoon list" })

-- Diagnostics
map("n", "<leader>do", vim.diagnostic.open_float, { desc = "Lsp diagnostic open" })
map("n", "<leader>dk", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "<leader>dj", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
-- map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })

-- trouble
map("n", "<leader>da", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics (Trouble)" })
map("n", "<leader>dc", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer Diagnostics (Trouble)" })
map("n", "<leader>sf", "<cmd>Trouble symbols toggle focus=false<cr>", { desc = "Symbols (Trouble)" })
map("n", "<leader>dl", "<cmd>Trouble loclist toggle<cr>", { desc = "Location List (Trouble)" })
map("n", "<leader>dq", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix List (Trouble)" })
map(
  "n",
  "<leader>dr",
  "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
  { desc = "LSP Definitions / references / ... (Trouble)" }
)

-- flash
map({ "n", "x", "o" }, "s", function()
  require("flash").jump()
end, { desc = "Flash" })
map({ "n", "x", "o" }, "S", function()
  require("flash").treesitter()
end, { desc = "Flash Treesitter" })
map("o", "r", function()
  require("flash").remote()
end, { desc = "Remote Flash" })
map({ "o", "x" }, "R", function()
  require("flash").treesitter_search()
end, { desc = "Treesitter Search" })
map("c", "<c-s>", function()
  require("flash").toggle()
end, { desc = "Toggle Flash Search" })

-- neogit
map("n", "<leader>gs", function()
  require("neogit").open()
end, { desc = "Open Neogit Menu" })
