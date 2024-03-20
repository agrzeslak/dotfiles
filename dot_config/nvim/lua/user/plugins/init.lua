return {
	{ "numToStr/Comment.nvim", opts = {} },
	"lewis6991/gitsigns.nvim",
	{
		"ggandor/leap.nvim",
		config = function()
			require("leap").create_default_mappings()
		end,
	},
	{ "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
	-- Navigate to project root using LSP or pattern
	{
		"ahmedkhalf/project.nvim",
		dependencies = { "neovim/nvim-lspconfig" },
		config = function()
			require("project_nvim").setup({
				-- TODO: remove because this is ignoring LSP root detection, but pyright
				-- is doing some really whacky things, so I've disabled it for now.
				detection_methods = { "pattern" },
			})
		end,
	},
	"jbyuki/venn.nvim",
	"RRethy/vim-illuminate",
	{
		"andymass/vim-matchup",
		config = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end,
	},
}
