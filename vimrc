" ~/.vimrc -- minimal, sane defaults + vim-plug
" Plugins are installed by the dotfiles installer (vim +PlugInstall).

set nocompatible
syntax on
filetype plugin indent on

" UI
set number
set ruler
set showcmd
set laststatus=2
set wildmenu

" Editing
set expandtab
set shiftwidth=2
set softtabstop=2
set tabstop=2
set autoindent
set backspace=indent,eol,start

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase

" Misc
set encoding=utf-8
set hidden
set mouse=a
set clipboard^=unnamed,unnamedplus

" --- vim-plug -------------------------------------------------------------
call plug#begin('~/.vim/plugged')
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-commentary'
call plug#end()
