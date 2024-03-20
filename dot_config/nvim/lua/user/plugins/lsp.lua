return {
	{
		"williamboman/mason.nvim",
		opts = {}
	},
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		config = function()
			-- Order important: mason -> mason-lspconfig -> nvim-lspconfig setup
			require("mason-lspconfig").setup()
			local lspconfig = require("lspconfig")
			require("mason-lspconfig").setup_handlers {
				-- This is a default handler that will be called for each
				-- installed server (also for new servers that are installed
				-- during a session)
				function(server_name)
					lspconfig[server_name].setup {}
				end,

				-- Manual dedicated handlers for servers where we want custom
				-- options
				["lua_ls"] = function()
					lspconfig.lua_ls.setup({
						settings = {
							Lua = {
								runtime = {
									-- Tell the language server which version of Lua you're using
									-- (most likely LuaJIT in the case of Neovim)
									version = 'LuaJIT',
								},
								diagnostics = {
									-- Get the language server to recognize the `vim` global
									globals = {
										'vim',
										'require'
									},
								},
								workspace = {
									-- luassert pop-up suppression https://github.com/folke/neodev.nvim/issues/88
									checkThirdParty = false,
									-- Make the server aware of Neovim runtime files
									library = vim.api.nvim_get_runtime_file("", true),
								},
								-- Do not send telemetry data containing a randomized but unique identifier
								telemetry = {
									enable = false,
								},
							},
						},
					})
				end,

				-- You can also override the default handler for specific servers by providing them as keys, like so:
				["rust_analyzer"] = function()
					lspconfig["rust_analyzer"].setup({
						settings = {
							["rust_analyzer"] = {
								cargo = {
									allFeatures = true,
								},
								completion = {
									postfix = {
										enable = false,
									},
								},
								imports = {
									group = {
										enable = false, -- All imports together, no empty lines
									}
								},
							},
						}
					})
				end,
			}
		end,
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
		},
		opts = {
			auto_update = true,
			debounce_hours = 24,
			ensure_installed = {
				"asm-lsp",
				"bash-language-server",
				"black",
				"cssmodules-language-server",
				"eslint_d",
				"eslint-lsp",
				"flake8",
				"isort",
				"jdtls",
				"lua-language-server",
				"markdownlint",
				"omnisharp-mono",
				"powershell-editor-services",
				"pyright",
				"prettierd",
				"rust-analyzer",
				"svelte-language-server",
				"tailwindcss-language-server",
				"typescript-language-server",
				"vale",
				"xmlformatter",
			}
		}
	},
	"neovim/nvim-lspconfig",
	{
		"stevearc/conform.nvim", -- Interface for formatters
		config = function()
			local conform = require("conform")
			local prettier = { { "prettierd", "prettier" } }
			conform.setup {
				formatters_by_ft = {
					-- Single list ({}) to sequentially run all available formatters
					-- Nested list ({{}}) to run only first available formatter
					css = prettier,
					html = prettier,
					javascript = prettier,
					typescript = prettier,
					javascriptreact = prettier,
					typescriptreact = prettier,
					markdown = prettier,
					svelte = prettier,
					yaml = prettier,
					lua = { "stylua" },
					python = { "isort", "black" },
					xml = { "xmlformat " },
				}
			}

			-- Set up <C-t> to format, with LSP as fallback
			vim.keymap.set(
				"n",
				"<leader>t",
				"<cmd>lua require'conform'.format{async=true,lsp_fallback=true}<CR>",
				{ noremap = true, silent = true }
			)
		end,

	},
	{
		"mfussenegger/nvim-lint", -- Interface for linters
		config = function()
			require("lint").linters_by_ft = {
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
	},
	{
		-- Show function signatures as you type
		"ray-x/lsp_signature.nvim",
		event = "VeryLazy",
		opts = {
			-- Only show argument lists, no docs
			doc_lines = 0,
			handler_opts = {
				border = "none"
			}
		},
	},
}
