local set = vim.keymap.set
local opts = { noremap = true, silent = true }

set("n", "<Space>", "<Nop>", opts)
vim.g.mapleader = " "
set("n", "<leader>w", "<cmd>w<cr>")
set("n", "<C-q>", "<cmd>qa!<cr>")
set("n", "<leader>o", ':e <C-R>=expand("%:p:h") . "/" <cr>')
set("", "H", "^")
set("", "L", "$")
set("v", "<C-h>", "<cmd>nohlsearch<cr>")
set("n", "<C-h>", "<cmd>nohlsearch<cr>")
set("n", "<leader><leader>", "<c-^>")
set("n", "<leader>,", ":set invlist<cr>")

-- Save as root
set("c", "w!!", ":w !sudo tee % > /dev/null")

-- Center search results
set("n", "n", "nzz", { silent = true })
set("n", "N", "Nzz", { silent = true })
set("n", "*", "*zz", { silent = true })
set("n", "#", "#zz", { silent = true })
set("n", "g*", "g*zz", { silent = true })

-- "very magic" (less escaping needed) regexes by default
set("n", "?", "?\\v")
set("n", "/", "/\\v")
set("c", "%s/", "%sm/")

-- Delete without yanking
set("n", "<leader>d", '"_d')
set("n", "<leader>D", '"_D')
set("n", "<leader>x", '"_x')

-- Do not instantly move to next result. Useful with cgn.
set("n", "*", "m`:keepjumps normal! *``<cr>")

-- Switching buffers
set("n", "gp", "<cmd>bp<cr>")
set("n", "gn", "<cmd>bn<cr>")

-- Make gf create the file under the cursor if it doesn't exist
set("n", "gf", ":e <cfile><cr>")

-- Telescope
-- set("n", "<leader>f", function() require'telescope.builtin'.find_files(require('telescope.themes').get_ivy({}))<cr>", opts)
-- TODO: Switch back to Telescope when proximity sort is implemented. As of now
--			 results are just slower and worse than this custom implementation
--			 https://github.com/natecraddock/telescope-zf-native.nvim/issues/14.
set("n", "<leader>f", "<cmd>Files<cr>", opts)
set("n", "<leader>/", function()
	require("telescope.builtin").live_grep(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>;", function()
	require("telescope.builtin").buffers(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>k", function()
	vim.lsp.buf.hover()
end, opts)
set("n", "<leader>r", function()
	vim.lsp.buf.rename()
end, opts)
set("n", "<leader>a", function()
	vim.lsp.buf.code_action()
end, opts)
set("n", "<leader>e", function()
	vim.diagnostic.open_float()
end, opts)
set("n", "<leader>q", function()
	vim.diagnostic.set_loclist()
end, opts)
set("n", "<leader>t", function()
	vim.lsp.buf.format({ async = true })
end, opts)
set("n", "<leader>s", function()
	require("telescope.builtin").lsp_document_symbols(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>S", function()
	require("telescope.builtin").lsp_workspace_symbols(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>'", function()
	require("telescope.builtin").resume(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>g", function()
	require("telescope.builtin").diagnostics(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>j", function()
	require("telescope.builtin").jumplist(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>*", function()
	require("telescope.builtin").grep_string(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "<leader>b", ":Gitsigns blame_line<cr>", opts)
set("n", "gr", function()
	require("telescope.builtin").lsp_references(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "gD", function()
	vim.lsp.buf.declaration()
end, opts)
set("n", "gd", function()
	require("telescope.builtin").lsp_definitions(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "gi", function()
	require("telescope.builtin").lsp_implementations(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "gy", function()
	require("telescope.builtin").lsp_type_definitions(require("telescope.themes").get_ivy({}))
end, opts)
set("n", "[d", function()
	vim.diagnostic.goto_prev()
end, opts)
set("n", "]d", function()
	vim.diagnostic.goto_next()
end, opts)
set("n", "<C-k>", function()
	vim.lsp.buf.signature_help()
end, opts)

-- PopUp menu (right-click)
vim.cmd([[
    aunmenu PopUp
]])
