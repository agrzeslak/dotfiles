return {
	"mfussenegger/nvim-lint", -- Interface for linters
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			css = { "eslint_d" },
			html = { "eslint_d" },
			javascript = { "eslint_d" },
			markdown = { "markdownlint" },
			python = { "flake8" },
			svelte = { "eslint_d" },
			typescript = { "eslint_d" },
		}

		vim.api.nvim_create_autocmd("BufWritePost", {
			callback = function()
				require("lint").try_lint()
			end,
		})
	end,
}
