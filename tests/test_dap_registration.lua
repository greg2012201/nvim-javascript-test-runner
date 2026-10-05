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

return T
