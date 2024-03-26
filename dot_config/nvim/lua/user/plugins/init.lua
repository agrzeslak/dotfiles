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
	"jbyuki/venn.nvim",
	"RRethy/vim-illuminate",
	{
		"andymass/vim-matchup",
		config = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end,
	},
}
