local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_once = child.stop,
	},
})

T["DAP registration"] = new_set()
T["DAP registration"]["DAP-enabled setup"] = new_set({
	hooks = {
		pre_case = function()
			child.lua([[
				_G.notifications = {}
				vim.notify = function(message, level)
					table.insert(_G.notifications, { message = message, level = level })
				end
			]])
		end,
	},
})

T["DAP registration"]["registers current file, folder, and line launch configs without replacing user configs"] = function()
	child.lua([[
		local unrelated_config = { name = "User config" }
		package.loaded["dap"] = {
			configurations = { javascript = { unrelated_config } },
			adapters = {
				["pwa-node"] = {
					type = "server",
					host = "127.0.0.1",
					port = 9229,
				},
			},
		}
		require("javascript-test-runner").setup({ dap = true })
	]])

	local result = child.lua_get([[
		(function()
			local configs = require("dap").configurations.javascript
			local purposes = { file = false, folder = false, line = false }
			local launch_config_count = 0
			for index, config in ipairs(configs) do
				if index > 1 then
					if config.type == "pwa-node" and config.request == "launch" then
						launch_config_count = launch_config_count + 1
					end
					local name = (config.name or ""):lower()
					for purpose in pairs(purposes) do
						if name:find(purpose, 1, true) then
							purposes[purpose] = true
						end
					end
				end
			end
			return {
				count = #configs,
				preserved_user_config = configs[1] and configs[1].name == "User config",
				launch_config_count = launch_config_count,
				purposes = purposes,
			}
		end)()
	]])

	eq(result.count, 4)
	eq(result.preserved_user_config, true)
	eq(result.launch_config_count, 3)
	eq(result.purposes, { file = true, folder = true, line = true })
end

T["DAP registration"]["DAP-enabled setup"]["aborts a launch when no project is found"] = function()
	child.lua([[
		local dap = {
			ABORT = {},
			adapters = {
				["pwa-node"] = {
					type = "server",
					host = "127.0.0.1",
					port = 9229,
				},
			},
			configurations = { javascript = {} },
		}
		package.loaded["dap"] = dap
		package.loaded["javascript-test-runner.project"] = {
			detect = function()
				return nil
			end,
		}
		require("javascript-test-runner").setup({ dap = true })
		local config = dap.configurations.javascript[1]()
		_G.abort_config = {
			has_launch_config = config.type == "pwa-node"
				and config.request == "launch"
				and type(config.name) == "string",
			returns_abort = config.program and config.program() == dap.ABORT,
		}
	]])

	eq(child.lua_get([[_G.abort_config.has_launch_config]]), true)
	eq(child.lua_get([[_G.abort_config.returns_abort]]), true)
end

T["DAP registration"]["DAP-enabled setup"]["notifies when nvim-dap is unavailable"] = function()
	child.lua([[
		package.loaded["dap"] = nil
		package.preload["dap"] = function()
			error("module 'dap' is unavailable")
		end
		_G.setup_succeeded = pcall(function()
			require("javascript-test-runner").setup({ dap = true })
		end)
	]])

	eq(child.lua_get([[_G.setup_succeeded]]), true)
	eq(child.lua_get([[
		_G.notifications[1] ~= nil
			and _G.notifications[1].level == vim.log.levels.ERROR
	]]), true)
	eq(child.lua_get([[
		_G.notifications[1] ~= nil
			and type(_G.notifications[1].message) == "string"
			and _G.notifications[1].message:lower():find("nvim-dap", 1, true) ~= nil
	]]), true)
end

T["DAP registration"]["DAP-enabled setup"]["notifies and installs no configs when pwa-node is unavailable"] = function()
	child.lua([[
		local unrelated_config = { name = "User config" }
		package.loaded["dap"] = {
			configurations = { javascript = { unrelated_config } },
			adapters = {},
		}
		require("javascript-test-runner").setup({ dap = true })
	]])

	eq(child.lua_get([[#require("dap").configurations.javascript]]), 1)
	eq(child.lua_get([[
		require("dap").configurations.javascript[1].name == "User config"
	]]), true)
	eq(child.lua_get([[
		_G.notifications[1] ~= nil
			and _G.notifications[1].level == vim.log.levels.ERROR
	]]), true)
	eq(child.lua_get([[
		_G.notifications[1] ~= nil
			and type(_G.notifications[1].message) == "string"
			and _G.notifications[1].message:lower():find("pwa-node", 1, true) ~= nil
	]]), true)
end

T["DAP registration"]["DAP-enabled setup"]["follows test terminal output without changing unrelated sessions"] = function()
	child.lua([[
		local dap = {
			ABORT = {},
			adapters = {
				["pwa-node"] = {
					type = "server",
					host = "127.0.0.1",
					port = 9229,
				},
			},
			configurations = {},
			listeners = {
				after = {},
			},
		}
		package.loaded["dap"] = dap
		package.loaded["javascript-test-runner.project"] = {
			detect = function()
				return { root = vim.fn.getcwd() }
			end,
			resolve_environment = function()
				return { framework = "jest", node = "/usr/bin/node" }
			end,
		}
		package.loaded["javascript-test-runner.backends"] = {
			build_debug_configuration = function()
				return {
					type = "pwa-node",
					request = "launch",
					console = "integratedTerminal",
				}
			end,
		}
		require("javascript-test-runner").setup({ dap = true })

		local config = dap.configurations.javascript[1]()
		local session = {
			config = vim.tbl_map(function(value)
				return value
			end, config),
			closed = false,
			on_close = {},
		}
		local follow = dap.listeners.after.event_initialized["javascript-test-runner-terminal-follow"]
		follow(session)
		vim.wait(100)

		local test_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(test_buffer)
		local test_job = vim.fn.termopen({ "sh", "-c", "sleep 0.2; seq 1 100" })
		session.term_buf = test_buffer
		vim.wait(5000, function()
			return vim.fn.jobwait({ test_job }, 0)[1] ~= -1
		end)
		vim.wait(50)
		local test_followed = vim.api.nvim_win_get_cursor(0)[1] > 1 and vim.fn.winsaveview().topline > 1

		local unrelated_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(unrelated_buffer)
		local unrelated_job = vim.fn.termopen({ "sh", "-c", "sleep 0.1; seq 1 100" })
		follow({
			config = { name = "User launch", console = "integratedTerminal" },
			term_buf = unrelated_buffer,
			closed = false,
			on_close = {},
		})
		vim.wait(5000, function()
			return vim.fn.jobwait({ unrelated_job }, 0)[1] ~= -1
		end)
		vim.wait(50)

		_G.terminal_follow_result = {
			test_followed = test_followed,
			unrelated_unchanged = vim.api.nvim_win_get_cursor(0)[1] == 1
				and vim.fn.winsaveview().topline == 1,
		}
	]])

	eq(child.lua_get([[_G.terminal_follow_result]]), {
		test_followed = true,
		unrelated_unchanged = true,
	})
end

return T
