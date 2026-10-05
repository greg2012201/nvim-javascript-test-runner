local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local child = MiniTest.new_child_neovim()
local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_once = child.stop,
	},
})

T["run errors"] = new_set()

T["run errors"]["notifies and does not start a job when no project is detected"] = function()
	child.lua([[
		require("javascript-test-runner.project").detect = function()
			return nil
		end
		_G.notifications = {}
		_G.jobstart_calls = 0
		vim.notify = function(message, level)
			table.insert(_G.notifications, { message = message, level = level })
		end
		vim.fn.jobstart = function()
			_G.jobstart_calls = _G.jobstart_calls + 1
			return 1
		end
		require("javascript-test-runner").setup()
	]])
	child.cmd("Test project")

	eq(child.lua_get([[_G.notifications[1] and _G.notifications[1].level == vim.log.levels.ERROR]]), true)
	eq(
		child.lua_get([[
			_G.notifications[1]
				and type(_G.notifications[1].message) == "string"
				and _G.notifications[1].message:find("package.json", 1, true) ~= nil
		]]),
		true
	)
	eq(child.lua_get([[_G.jobstart_calls]]), 0)
end

T["run errors"]["notifies and does not start a job for an unsupported detected framework"] = function()
	local project_root = absolute_path("tests/fixtures/npm-jest")
	child.lua(string.format(
		[[
			local project_root = %q
			require("javascript-test-runner.project").detect = function()
				return {
					root = project_root,
					package_json = project_root .. "/package.json",
				}
			end
			require("javascript-test-runner.framework").detect = function()
				return "mocha"
			end
			_G.notifications = {}
			_G.jobstart_calls = 0
			vim.notify = function(message, level)
				table.insert(_G.notifications, { message = message, level = level })
			end
			vim.fn.jobstart = function()
				_G.jobstart_calls = _G.jobstart_calls + 1
				return 1
			end
			require("javascript-test-runner").setup()
		]],
		project_root
	))
	child.cmd("Test project")

	eq(child.lua_get([[_G.notifications[1] and _G.notifications[1].level == vim.log.levels.ERROR]]), true)
	eq(
		child.lua_get([[
			_G.notifications[1]
				and type(_G.notifications[1].message) == "string"
				and _G.notifications[1].message:lower():find("mocha", 1, true) ~= nil
				and (
					_G.notifications[1].message:lower():find("unsupported", 1, true) ~= nil
					or _G.notifications[1].message:lower():find("not supported", 1, true) ~= nil
				)
		]]),
		true
	)
	eq(child.lua_get([[_G.jobstart_calls]]), 0)
end

T["run errors"]["reports an error when the executable cannot be launched"] = function()
	child.lua([[
		local project_root = vim.fn.fnamemodify("tests/fixtures/npm-jest/package.json", ":p:h")
		vim.cmd("cd " .. vim.fn.fnameescape(project_root))
		_G.notifications = {}
		_G.jobstart_calls = 0
		vim.notify = function(message, level)
			table.insert(_G.notifications, { message = message, level = level })
		end
		vim.fn.jobstart = function()
			_G.jobstart_calls = _G.jobstart_calls + 1
			return -1
		end
		require("javascript-test-runner").setup()
	]])
	child.cmd("Test project")

	eq(child.lua_get([[_G.jobstart_calls]]), 1)
	eq(child.lua_get([[_G.notifications[1] and _G.notifications[1].level == vim.log.levels.ERROR]]), true)
	eq(
		child.lua_get([[
			_G.notifications[1]
				and type(_G.notifications[1].message) == "string"
				and #_G.notifications[1].message > 0
				and (
					_G.notifications[1].message:lower():find("start", 1, true) ~= nil
					or _G.notifications[1].message:lower():find("launch", 1, true) ~= nil
				)
		]]),
		true
	)
end

return T
