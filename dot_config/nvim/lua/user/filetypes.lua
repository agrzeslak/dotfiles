vim.api.nvim_create_autocmd("Filetype", {
	pattern = "rust",
	command = "set textwidth=100 colorcolumn=101",
})

-- Filetypes where tab = 2 spaces
vim.api.nvim_create_autocmd("Filetype", {
	pattern = {
		"css",
		"html",
		"javascript",
		"javascriptreact",
		"json",
		"lua",
		"markdown",
		"typescript",
		"typescriptreact",
		"typescriptreact",
	},
	command = "setlocal shiftwidth=2 tabstop=2",
})

-- Filetypes where tab = 4 spaces
vim.api.nvim_create_autocmd("Filetype", {
	pattern = { "cs" },
	command = "setlocal shiftwidth=4 tabstop=4",
})

-- Git commit messages
vim.api.nvim_create_autocmd("Filetype", {
	pattern = "gitcommit",
	command = "setlocal textwidth=72 colorcolumn=73",
})

-- Enable spellchecking
vim.api.nvim_create_autocmd("Filetype", {
	pattern = { "gitcommit", "markdown", "mail", "text" },
	command = "setlocal spell",
})

-- PowerShell https://poshcode.gitbook.io/powershell-practice-and-style/style-guide/code-layout-and-formatting
vim.api.nvim_create_autocmd("Filetype", {
	pattern = "ps1",
	command = "setlocal textwidth=115 colorcolumn=116",
})
