return {
	"plasticboy/vim-markdown",
	ft = { "markdown" },
	dependencies = { "godlygeek/tabular" },
	config = function()
		-- Support front-matter
		vim.g.vim_markdown_frontmatter = 1
		-- 'o' on a list item should insert at same level
		vim.g.vim_markdown_new_list_item_indent = 0
		-- Don't add bullets when wrapping:
		-- https://github.com/preservim/vim-markdown/issues/232
		vim.g.vim_markdown_auto_insert_bullets = 0
	end,
}
