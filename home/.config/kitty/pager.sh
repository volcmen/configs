#!/usr/bin/env bash

# This safely passes Kitty's scrollback into a Neovim terminal buffer
exec nvim \
  -u NONE \
  -c "map <silent> q :qa!<CR>" \
  -c "set shell=bash scrollback=100000 termguicolors laststatus=0 clipboard+=unnamedplus" \
  -c "autocmd TermEnter * stopinsert" \
  -c "autocmd TermClose * normal G" \
  -c "terminal cat /dev/fd/63" 63<&0 0</dev/null
