return {
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({ ensure_installed = "all" })
		end,
	},
	{
		"nvim-treesitter/playground",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
	},
	"JoosepAlviste/nvim-ts-context-commentstring",
	config = function()
		vim.g.skip_ts_context_commentstring_module = true
		require("ts_context_commentstring").setup({
			enable_autocmd = false,
		})
		require("Comment").setup({
			pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
		})
	end,
	dependencies = {
		"numToStr/Comment.nvim",
		"nvim-treesitter/nvim-treesitter",
	},
}
