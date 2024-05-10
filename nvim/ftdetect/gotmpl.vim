" Might be useful
" https://www.reddit.com/r/neovim/comments/sqr6r5/helm_charts_for_kubernetes_in_nvim_bad_experience/
autocmd BufNewFile,BufRead * if search('{{.\+}}', 'nw') | setlocal filetype=gotmpl | endif

