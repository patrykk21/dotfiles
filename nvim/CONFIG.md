# Key Bindings

## CMD key on OSX

I found a hack to make CMD key work inside vim with kitty.
In `~/.config/kitty/cmd-remap.conf` you can find a remap to send the `0x37` character to the buffer
which [based on this page](https://stackoverflow.com/questions/3202629/where-can-i-find-a-list-of-mac-virtual-key-codes)
equals to the CMD key.
You can then map such key in `.lua` files like `nnoremap("<CHAR-0x37>s", "<cmd>echo 'ok'<CR>")`.
There's also a file in `~/.config/nvim/lua/cmd-remap.lua` that tries to map `<CHAR-0x037>` into `<D>`. That would be amazing
but I still had no success with it.

## Families

Most key bindings are done in the form of `<leader>{family}{keybind}` where `{family}` is a grouping
per key bind function.
This is done in order to be more mnemonic than random combination of letters.
Often the `{keybind}` following the `{family}` key will be either the initial of a word of the function
called, either the initials of the sentence of the function called.

| key      | function |
| -------- | -------- |
| `<none>` | generic  |
| `l`      | LSP      |

## Table

### General

| mode | key bind          | function                             | explanation                                                              |
| ---- | ----------------- | ------------------------------------ | ------------------------------------------------------------------------ |
| n    | `<ctrl>+y`        | -                                    | Moves screen up {N} lines                                                |
| n    | `<ctrl>+e`        | -                                    | Moves screen down {N} lines                                              |
| n    | `<ctrl>+u`        | -                                    | Moves cursor & screen up {n} lines (default: half page)                  |
| n    | `<ctrl>+d`        | -                                    | Moves cursor & screen down {n} lines (default: half page)                |
| n    | `<ctrl>+b`        | -                                    | Moves screen up {N} pages                                                |
| n    | `<ctrl>+f`        | -                                    | Moves screen down {N} pages                                              |
| a    | `<cmd>+s`         | :w                                   | Saves current buffer                                                     |
| a    | `<cmd>+<shift>+s` | :wq                                  | Saves current buffer and quits it                                        |
| n    | `<alt>+n`         | 'illuminate'.goto_next_reference     | Jumps to next matching token under cursor                                |
| n    | `<alt>+p`         | 'illuminate'.goto_prev_reference     | Jumps to next matching token under cursor                                |
| o    | `<alt>+i`         | 'illuminate'.textobj_select          | Jumps to next matching token under cursor                                |
| x    | `<alt>+i`         | 'illuminate'.textobj_select          | Jumps to next matching token under cursor                                |
| n    | `<leader>ex`      | :Ex                                  | Opens netrw                                                              |

### LSP

| mode | key bind          | function                             | explanation                                                              |
| ---- | ----------------- | ------------------------------------ | ------------------------------------------------------------------------ |
| n    | `<leader>dd`      | diagnostic.open_float                | Opens float with diagnostics for cursor position                         |
| n    | `<leader>dn`      | diagnostic.goto_next                 | Moves to the next diagnostic in the dropdown                             |
| n    | `<leader>dp`      | diagnostic.goto_prev                 | Moves to the previous diagnostic in the dropdown                         |
| n    | `<leader>dl`      | diagnostic.setloclist                | Opens new window with list of diagnostics                                |
| n    | `<leader>gD`      | lsp.buf.declaration                  | Jumps to declaration                                                     |
| n    | `<leader>gd`      | lsp.buf.definition                   | Jumps to definition                                                      |
| n    | `<leader>gi`      | lsp.buf.implementation               | Jumps to implementation                                                  |
| n    | `<leader>gt`      | lsp.buf.type_definition              | Jumps to definition of the type under cursor position                    |
| n    | `<leader>h`       | lsp.buf.hover                        | Opens float with info for cursor position                                |
| n    | `<leader>sh`      | lsp.buf.signature_help               | Opens float with signature for cursor position                           |
| n    | `<leader>ref`     | lsp.buf.references                   | Opens new window with list of references of symbol under cursor position |
| n    | `<leader>ca`      | lsp.buf.code_action                  | Selects a code action available at cursor position                       |
| n    | `<leader>r`       | lsp.buf.rename                       | Renames all references to the symbol under cursor position               |
| n    | `<leader>ff`      | lsp.buf.formatting                   | Formats the current buffer                                               |
| n    | `<leader>wa`      | lsp.buf.add_workspace_folder         | Adds workspace dir inserted in command line to workspaces list           |
| n    | `<leader>wr`      | lsp.buf.remove_workspace_folder      | Removes workspace dir inserted in command line from workspaces list      |
| n    | `<leader>wl`      | lsp.buf.list_workspace_folders       | Lists workspace folders                                                  |

### Telescope

| mode | key bind          | function                             | explanation                                                              |
| ---- | ----------------- | ------------------------------------ | ------------------------------------------------------------------------ |
| n    | `<leader>fs`      | :Telescope find_files                | Opens panel to find files                                                |
| n    | `<leader>fS`      | :Telescope live_grep                 | Opens panel to find tokens in files                                      |
| n    | `<leader>fw`      | :Telescope current_buffer_fuzzy_find | Opens panel to find token in current file                                |
| n    | `<leader>fb`      | :Telescope buffers                   | Opens panel to find buffers                                              |
| n    | `<leader>fh`      | :Telescope help_tags                 | Opens panel to find token in help page                                   |
| n    | `<leader>fq`      | :Telescope quickfix                  | Opens panel with list of quickfix files                                  |
| n    | `<leader>fc`      | :Telescope commands                  | Opens panel to find commands                                             |
| n    | `<leader>fr`      | :Telescope registers                 | Opens panel to find registers                                            |

#### In viewer


| mode | key bind            | explanation                                                              |
| ---- | ------------------- | ------------------------------------------------------------------------ |
| a    | `<ctrl>+n`/`<down>` | Next item                                                                |
| a    | `<ctrl>+p`/`<up>`   | Previous item                                                            |
| n    | `j`/`k`             | Next item / Previous item                                                |
| n    | `H`/`M`/`L`         | Select High / Middle / Low                                               |
| n    | `gg`/`G`            | Select the first / last item                                             |
| a    | `<cr>`              | Confirm selection                                                        |
| a    | `<ctrl>+x`          | Go to file selection as split                                            |
| a    | `<ctrl>+v`          | Go to file selection as vertical split                                   |
| a    | `<ctrl>+t`          | Go to file selection in a new tab                                        |
| a    | `<ctrl>+u`          | Scroll up in preview window                                              |
| a    | `<ctrl>+d`          | Scroll down in preview window                                            |
| i    | `<ctrl>+/`          | Show mappings                                                            |
| n    | `?`                 | Show mappings                                                            |
| a    | `<ctrl>+c`          | Close telescope                                                          |
| n    | `<esc>`             | Close telescope                                                          |
| n    | `<tab>`             | Toggle selection and move to next selection                              |
| n    | `<shift>+<tab>`     | Toggle selection and move to previous selection                          |
| n    | `<ctrl>+q`          | Send all items not filtered to quickfixlist                              |
| n    | `<alt>+q`           | Send all items selected to quickfixlist                                  |

