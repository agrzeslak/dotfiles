vim.opt.shell = "/bin/bash" -- Fish doesn't play well with others
vim.g.mapleader = " "
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus" -- Yank/paste to/from system clipboard
vim.opt.encoding = "utf-8"
vim.opt.wrap = false
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.scrolloff = 2
vim.opt.signcolumn = "yes"
vim.opt.splitbelow = true -- Open new horizontal split below
vim.opt.splitright = true -- Opens new virtical split to right
vim.opt.undofile = true -- ~/.local/state/nvim/undo
vim.opt.wildmode = "list:longest" -- List options and complete to longest match
vim.opt.wildignore =
	".hg,.svn,*~,*.png,*.jpg,*.gif,*.settings,Thumbs.db,*.min.js,*.swp,publish/*,intermediate/*,*.o,*.hi,Zend,vendor"
vim.opt.shiftwidth = 8
vim.opt.tabstop = 8 -- Clearly differentiate tabs, and helps with compatibility with older codebases or programs
vim.opt.softtabstop = -1 -- Use shiftwidth as softtabstop
vim.opt.expandtab = false
-- tc: wrap text and comments using textwidth
-- r: continue comments when pressing ENTER in I mode
-- q: enable formatting of comments with gq
-- n: detect lists for formatting
-- b: auto-wrap in insert mode, and do not wrap old long lines
vim.opt.formatoptions = "tcrqnb"
vim.opt.ignorecase = true
vim.opt.smartcase = true -- Case sensitive search if upper case characters are provided
vim.opt.gdefault = true -- /g suffix is implied when search and replacing, override with /g
vim.opt.cursorline = true
vim.opt.vb = true -- Never audibly beep
vim.opt.colorcolumn = "81" -- Vertical column 1 after textwidth to show it as the boundary
vim.opt.textwidth = 80
vim.opt.foldlevelstart = 99 -- Start with everything unfolded
-- Diffs (nvim -d)
vim.opt.diffopt:append("iwhite") -- Ignore whitespace
vim.opt.diffopt:append("algorithm:histogram")
vim.opt.diffopt:append("indent-heuristic")
