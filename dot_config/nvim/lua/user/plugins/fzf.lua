return {
	"junegunn/fzf.vim",
	dependencies = {
		{ "junegunn/fzf", dir = "~/.fzf", build = "./install --all" },
	},
	build = "cargo install proximity-sort",
	config = function()
		-- stop putting a giant window over my editor
		vim.g.fzf_layout = { down = "~20%" }
		-- when using :Files, pass the file list through
		--
		--   https://github.com/jonhoo/proximity-sort
		--
		-- to prefer files closer to the current file.
		function list_cmd()
			local base = vim.fn.fnamemodify(vim.fn.expand("%"), ":h:.:S")
			if base == "." then
				-- if there is no current file,
				-- proximity-sort can't do its thing
				return "fd --type file --follow"
			else
				return vim.fn.printf(
					"fd --type file --follow | proximity-sort %s",
					vim.fn.shellescape(vim.fn.expand("%"))
				)
			end
		end

		vim.api.nvim_create_user_command("Files", function(arg)
			vim.fn["fzf#vim#files"](arg.qargs, { source = list_cmd(), options = "--tiebreak=index" }, arg.bang)
		end, { bang = true, nargs = "?", complete = "dir" })
	end,
}
