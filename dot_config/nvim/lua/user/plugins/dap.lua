return {
	{
		"mfussenegger/nvim-dap",
		config = function()
			local dap = require("dap")
			-- Key mappings
			local opts = { noremap = true, silent = true }
			vim.keymap.set("n", "<leader>@", function()
				dap.toggle_breakpoint()
			end, opts)

			-- .NET, install netcoredbg
			dap.adapters.coreclr = {
				type = "executable",
				command = "/usr/bin/netcoredbg",
				args = { "--interpreter=vscode" },
			}
			dap.configurations.cs = {
				{
					type = "coreclr",
					name = "launch - netcoredbg",
					request = "launch",
					program = function()
						return vim.fn.input("Path to dll", vim.fn.getcwd() .. "/bin/Debug", "file")
					end,
				},
			}

			-- Right-click UI
			vim.cmd([[
				anoremenu PopUp.[DAP]\ Continue    <cmd>lua require'dap'.continue()<CR>
				anoremenu PopUp.[DAP]\ Toggle\ breakpoint <cmd>lua require'dap'.toggle_breakpoint()<CR>
			]])
		end,
	},
	{
		-- Java: install jdtls
		"mfussenegger/nvim-jdtls",
		dependencies = { "mfussenegger/nvim-dap" },
		ft = { "java" },
		config = function()
			local jdtls = require("jdtls")
			local dap = require("dap")

			local config = {
				cmd = { "/usr/bin/jdtls" },
				root_dir = vim.fs.dirname(vim.fs.find({ "gradlew", ".git", "mvnw" }, { upward = true })[1]),
				init_options = {
					bundles = {
						"/home/andrzej/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar",
					},
				},
				on_attach = function(client, bufnr)
					jdtls.setup_dap({ hotcodereplace = "auto" })
					require("jdtls.dap").setup_dap_main_class_configs()

					dap.configurations.java = {
						{
							type = "java",
							name = "Launch",
							request = "launch",
							program = "${file}",
						},
						{
							type = "java",
							name = "Attach",
							request = "attach",
							host = function()
								return vim.fn.input("Hostname: ")
							end,
							port = function()
								return tonumber(vim.fn.input("Port: "))
							end,
						},
					}

					-- Add any other Java-specific keymaps or settings here
				end,
			}

			jdtls.start_or_attach(config)
		end,
	},
	{
		"theHamsta/nvim-dap-virtual-text",
		dependencies = {
			"mfussenegger/nvim-dap",
			"nvim-treesitter/nvim-treesitter",
		},
		opts = { virt_text_pos = "eol" },
	},
	{
		"rcarriga/nvim-dap-ui",
		dependencies = {
			"mfussenegger/nvim-dap",
			"nvim-neotest/nvim-nio",
		},
		config = function()
			local dap, dapui = require("dap"), require("dapui")
			dapui.setup()

			local opts = { noremap = true, silent = true }
			vim.keymap.set("n", "<leader>!", function()
				dapui.toggle()
			end, opts)

			dap.listeners.before.attach.dapui_config = function()
				dapui.open()
			end
			dap.listeners.before.launch.dapui_config = function()
				dapui.open()
			end
			-- dap.listeners.before.event_terminated.dapui_config = function()
			-- 	dapui.close()
			-- end
			-- dap.listeners.before.event_exited.dapui_config = function()
			-- 	dapui.close()
			-- end
		end,
	},
}
