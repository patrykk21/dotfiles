local cmp = require("cmp")

return {
  {
    "hrsh7th/nvim-cmp",
    opts = {
      mapping = {
        ["<S-Tab>"] = function(callback)
          callback()
        end,
        ["<CR>"] = function(callback)
          callback()
        end,
        ["<Down>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
          else
            fallback()
          end
        end, {
          "i",
          "s",
        }),
        ["<Up>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
          else
            fallback()
          end
        end, {
          "i",
          "s",
        }),
        ["<Tab>"] = cmp.mapping.confirm({
          behavior = cmp.ConfirmBehavior.Insert,
          select = true,
        }),
      },
    },
    view = {
      entries = {
        follow_cursor = true
      }
    }
  },
}
