local builtin = require("statuscol.builtin")

local cfg = {
  relculright = true,
  segments = {
    {
      sign = { name = { "Diagnostic" }, maxwidth = 1, colwidth = 2, auto = false, wrap = true },
      click = "v:lua.ScSa",
    },
    { text = { builtin.lnumfunc }, click = "v:lua.ScLa" },
    { text = { " " } },
    {
      sign = { namespace = { "gitsigns" }, maxwidth = 1, colwidth = 2, auto = false, name = { ".*" } },
      click = "v:lua.ScSa",
    },
    {
      text = { builtin.foldfunc },
      click = "v:lua.ScFa",
    },
    { text = { " " } },
  },
}

return cfg
