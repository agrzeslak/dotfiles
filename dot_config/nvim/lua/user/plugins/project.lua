return {
	"ahmedkhalf/project.nvim",
	dependencies = { "neovim/nvim-lspconfig" },
	config = function()
		require("project_nvim").setup({
			-- TODO: remove because this is ignoring LSP root detection, but pyright
			-- is doing some really whacky things, so I've disabled it for now.
			detection_methods = { "pattern" },
			patterns = {
				".git",
				"_darcs",
				".hg",
				".bzr",
				".svn",
				"Makefile",
				"package.json",
				">pentests",
				">.config",
			},
		})
	end,
}
