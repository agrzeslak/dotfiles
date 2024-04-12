return {
	{
		"saadparwaiz1/cmp_luasnip", -- Completions from LuaSnip
		dependencies = {
			"L3MON4D3/LuaSnip",
		},
	},
	-- Completion engine itself
	{
		"hrsh7th/nvim-cmp",
		dependencies = {
			"L3MON4D3/LuaSnip", -- Snippet engine required
			"hrsh7th/cmp-buffer", -- Completions sourced from buffer
			"hrsh7th/cmp-path", -- Completions sourced from filesystem paths
			"hrsh7th/cmp-nvim-lua", -- Completions sourced from Neovim's Lua API
			"hrsh7th/cmp-nvim-lsp", -- Completions sourced from LSP
		},
		config = function()
			local cmp = require("cmp")
			cmp.setup({
				snippet = {
					-- nvim-cmp requires a snippet engine; we're using LuaSnip
					expand = function(args)
						require("luasnip").lsp_expand(args.body)
					end,
				},
				mapping = {
					-- Tab to complete. C-n/C-p to select.
					["<Tab>"] = cmp.mapping.confirm({ select = true }),
					["<C-n>"] = cmp.mapping(cmp.mapping.select_next_item(), { "i", "c" }),
					["<C-p>"] = cmp.mapping(cmp.mapping.select_prev_item(), { "i", "c" }),
					["<C-d>"] = cmp.mapping.scroll_docs(4),
					["<C-u>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(8),
					["<C-b>"] = cmp.mapping.scroll_docs(-8),
				},
				-- Order of sources here = order in which they are suggested.
				-- Can configure:
				--   - keyword_length
				--   - priority
				--   - max_item_count
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "nvim_lua" },
				}, {
					{ name = "path" },
					{ name = "luasnip" },
					{ name = "buffer", keyword_length = 5 },
				}),
				experimental = {
					ghost_text = true,
				},
			})

			-- Completion from the buffer for when forward searching
			cmp.setup.cmdline("/", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = "buffer" },
				},
			})

			-- Completion from the buffer for when reverse searching
			cmp.setup.cmdline("?", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = "buffer" },
				},
			})

			-- Enable completion in the command line
			cmp.setup.cmdline(":", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = "path" },
				}, {
					{
						name = "cmdline",
						option = {
							ignore_cmds = { "Man", "!" },
						},
					},
				}),
			})
		end,
	},
}
