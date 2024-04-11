return	{
		"stevearc/conform.nvim", -- Interface for formatters
		config = function()
			local conform = require("conform")
			local prettier = { { "prettierd", "prettier" } }
			conform.setup({
				formatters_by_ft = {
					-- Single list ({}) to sequentially run all available formatters
					-- Nested list ({{}}) to run only first available formatter
					css = prettier,
					html = prettier,
					javascript = prettier,
					typescript = prettier,
					javascriptreact = prettier,
					typescriptreact = prettier,
					json = prettier,
					markdown = prettier,
					svelte = prettier,
					yaml = prettier,
					lua = { "stylua" },
					python = { "isort", "black" },
					xml = { "xmlformat " },
				},
			})

			-- Set up <C-t> to format, with LSP as fallback
			vim.keymap.set(
				"n",
				"<leader>t",
				"<cmd>lua require'conform'.format{async=true,lsp_fallback=true}<CR>",
				{ noremap = true, silent = true }
			)
		end,
	}
