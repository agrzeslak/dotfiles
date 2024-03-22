return {
	"L3MON4D3/LuaSnip", -- Snippet engine
	config = function()
		local ls = require("luasnip")
		local types = require("luasnip.util.types")

		ls.setup()
		ls.config.set_config({
			history = true, -- Keep last snippet around so you can jump back in
			updateevents = "TextChanged, TextChangedI", -- Dynamic snippets update as you type
			ext_opts = {
				[types.choiceNode] = {
					active = {
						virt_text = { { "<-", "Error" } },
					},
				},
			},
		})

		-- Expand current snippet item or jump to next item
		vim.keymap.set({ "i", "s" }, "<C-k>", function()
			if ls.expand_or_jumpable() then
				ls.expand_or_jump()
			end
		end, { noremap = true, silent = true })

		-- Go back to previous item in snippet
		vim.keymap.set({ "i", "s" }, "<C-h>", function()
			if ls.jumpable(-1) then
				ls.jump(-1)
			end
		end, { noremap = true, silent = true })

		-- Select from a list of options
		vim.keymap.set("i", "<C-l>", function()
			if ls.choice_active() then
				ls.change_choice(1)
			end
		end)

		-- Source LuaSnips file againsto reload snippets without restarting Neovim
		vim.keymap.set("n", "<leader>-", "<cmd>source ~/.config/nvim/lua/user/plugins/luasnip.lua<cr>")

		-- Source all snippet files
		for _, ft_path in ipairs(vim.api.nvim_get_runtime_file("lua/user/snippets/*.lua", true)) do
			loadfile(ft_path)()
		end
	end,
}
