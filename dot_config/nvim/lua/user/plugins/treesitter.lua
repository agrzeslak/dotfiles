-- ==============================================================================
-- Treesitter
-- ==============================================================================
--
-- We track nvim-treesitter's `main` branch, not `master`. `master` is frozen at
-- the pre-0.11 query API, where a predicate/directive handler received
-- `match[capture_id]` as a single TSNode. Nvim 0.11 changed that to a list of
-- nodes and 0.12 removed the compatibility shim, so every handler in
-- `nvim-treesitter/query_predicates.lua` called a method on a plain list:
--
--     .../vim/treesitter.lua:197: attempt to call method 'range' (a nil value)
--
-- Markdown triggered it on every buffer via `#set-lang-from-info-string!` while
-- resolving fenced-code-block injections.
--
-- `main` is a full rewrite and effectively a different plugin: no
-- `configs.setup`, no modules, and no lazy-loading. It only installs parsers and
-- ships queries; the features built on them are enabled below against Nvim's own
-- treesitter API.
--
-- Requires `tree-sitter-cli` (>= 0.26.1) on $PATH -- `main` builds every parser
-- from source. Install it from your package manager, not npm.

-- Parsers to keep installed. `master`'s `ensure_installed = "all"` is not
-- practical on `main` (323 parsers, each compiled locally), so this is scoped to
-- what this config actually touches -- filetypes.lua, conform, nvim-lint, jdtls
-- and the snippets. `:TSInstall <lang>` adds more on demand.
local ensure_installed = {
	"bash",
	"c",
	"c_sharp",
	"comment",
	"cpp",
	"css",
	"csv",
	"diff",
	"dockerfile",
	"fish",
	"gitattributes",
	"gitcommit",
	"gitignore",
	"git_config",
	"git_rebase",
	"go",
	"html",
	"java",
	"javascript",
	"jsdoc",
	"json",
	"json5",
	"lua",
	"luadoc",
	"make",
	"markdown",
	"markdown_inline",
	"powershell",
	"printf",
	"python",
	"query",
	"regex",
	"rust",
	"sql",
	"svelte",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"xml",
	"yaml",
}

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		-- `main` does not support lazy-loading, and parsers are only guaranteed to
		-- work with the plugin revision that installed them, hence the `build`.
		lazy = false,
		build = ":TSUpdate",
		config = function()
			-- Deliberately no `setup()` call: its only option is `install_dir`, and
			-- the default (stdpath("data") .. "/site") is already on 'runtimepath'.
			-- `install` is asynchronous and a no-op for parsers already present.
			require("nvim-treesitter").install(ensure_installed)

			-- Highlighting belongs to Nvim, not to the plugin. Nvim's own ftplugins
			-- only start it for lua, markdown, help and query, so start it for every
			-- filetype whose parser we actually have installed. Calling `start()` on
			-- an already-highlighted buffer is a no-op, so overlapping with those
			-- ftplugins is harmless.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
				callback = function(args)
					local lang = vim.treesitter.language.get_lang(args.match)
					-- `language.add` returns nil rather than raising when the parser is
					-- missing, which is the normal case for filetypes off the list above.
					if lang and vim.treesitter.language.add(lang) then
						vim.treesitter.start(args.buf, lang)
					end
				end,
			})
		end,
	},
	-- `nvim-treesitter/playground` is intentionally gone: it is archived and only
	-- works against `master`. Nvim ships `:InspectTree` and `:EditQuery` instead.
	{
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
	},
}
