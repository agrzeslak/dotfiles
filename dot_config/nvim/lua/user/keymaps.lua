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

-- Make j and k move by visual line, not actual line, when text is soft-wrapped
set("n", "j", "gj")
set("n", "k", "gk")

-- Delete without yanking
set("n", "<leader>d", '"_d')
set("n", "<leader>D", '"_D')
set("n", "<leader>x", '"_x')

-- Do not instantly move to next result. Useful with cgn.
set("n", "*", "m`:keepjumps normal! *``<cr>")

-- Switching buffers
set("n", "gp", "<cmd>bp<cr>")
set("n", "gn", "<cmd>bn<cr>")

-- Telescope
-- set("n", "<leader>f", "<cmd>lua require'telescope.builtin'.find_files(require('telescope.themes').get_ivy({}))<cr>", opts)
-- TODO: Switch back to Telescope when proximity sort is implemented. As of now
--			 results are just slower and worse than this custom implementation
--			 https://github.com/natecraddock/telescope-zf-native.nvim/issues/14.
set("n", "<leader>f", "<cmd>Files<cr>", opts)
set(
	"n",
	"<leader>/",
	"<cmd>lua require'telescope.builtin'.live_grep(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set("n", "<leader>;", "<cmd>lua require'telescope.builtin'.buffers(require('telescope.themes').get_ivy({}))<cr>", opts)
set("n", "<leader>k", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
set("n", "<leader>r", "<cmd>lua vim.lsp.buf.rename()<CR>", opts)
set("n", "<leader>a", "<cmd>lua vim.lsp.buf.code_action()<CR>", opts)
set("n", "<leader>e", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)
set("n", "<leader>q", "<cmd>lua vim.diagnostic.set_loclist()<CR>", opts)
set("n", "<leader>t", "<cmd>lua vim.lsp.buf.format { async = true }<CR>", opts)
set(
	"n",
	"<leader>s",
	"<cmd>lua require'telescope.builtin'.lsp_document_symbols(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set(
	"n",
	"<leader>S",
	"<cmd>lua require'telescope.builtin'.lsp_workspace_symbols(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set("n", "<leader>'", "<cmd>lua require'telescope.builtin'.resume(require('telescope.themes').get_ivy({}))<cr>", opts)
set(
	"n",
	"<leader>g",
	"<cmd>lua require'telescope.builtin'.diagnostics(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set("n", "<leader>j", "<cmd>lua require'telescope.builtin'.jumplist(require('telescope.themes').get_ivy({}))<cr>", opts)
set(
	"n",
	"<leader>*",
	"<cmd>lua require'telescope.builtin'.grep_string(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set("n", "<leader>b", ":Gitsigns blame_line<cr>", opts)
set("n", "gr", "<cmd>lua require'telescope.builtin'.lsp_references(require('telescope.themes').get_ivy({}))<cr>", opts)
set("n", "gD", "<cmd>lua vim.lsp.buf.declaration()<CR>", opts)
set("n", "gd", "<cmd>lua require'telescope.builtin'.lsp_definitions(require('telescope.themes').get_ivy({}))<cr>", opts)
set(
	"n",
	"gi",
	"<cmd>lua require'telescope.builtin'.lsp_implementations(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set(
	"n",
	"gy",
	"<cmd>lua require'telescope.builtin'.lsp_type_definitions(require('telescope.themes').get_ivy({}))<cr>",
	opts
)
set("n", "[d", "<cmd>lua vim.diagnostic.goto_prev()<CR>", opts)
set("n", "]d", "<cmd>lua vim.diagnostic.goto_next()<CR>", opts)
set("n", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)

-- PopUp menu (right-click)
vim.cmd([[
    aunmenu PopUp
    anoremenu PopUp.Go\ To\ Definition          <cmd>lua require'telescope.builtin'.lsp_definitions(require('telescope.themes').get_ivy({}))<cr>
    anoremenu PopUp.Go\ To\ References          <cmd>lua require'telescope.builtin'.lsp_references(require('telescope.themes').get_ivy({}))<cr>
    anoremenu PopUp.Go\ To\ Declaration         <cmd>lua vim.lsp.buf.declaration()<CR>
    anoremenu PopUp.Go\ To\ Implementations     <cmd>lua require'telescope.builtin'.lsp_implementations(require('telescope.themes').get_ivy({}))<cr>
    anoremenu PopUp.Go\ To\ Type\ Definitions   <cmd>lua require'telescope.builtin'.lsp_type_definitions(require('telescope.themes').get_ivy({}))<cr>
    anoremenu PopUp.Hover                       <cmd>lua vim.lsp.buf.hover()<CR>
    anoremenu PopUp.Signature\ Help             <cmd>lua vim.lsp.buf.signature_help()<CR>
    anoremenu PopUp.Rename                      <cmd>lua vim.lsp.buf.rename()<CR>
]])
