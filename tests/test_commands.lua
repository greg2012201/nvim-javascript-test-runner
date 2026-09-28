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

T["command execution"] = new_set()

T["command execution"]["notifies with a message if invocation error is missing"] = function()
	child.lua([[
		local commands = require("javascript-test-runner.commands")
		local api = require("javascript-test-runner.api")
		api.build_jest_invocation = function()
			return nil
		end
		vim.notify = function(message)
			_G.notification = message
		end
		commands.run_jest("file")
	]])

	eq(child.lua_get([[_G.notification]]), "Could not build test invocation.")
end

T["command execution"]["starts the terminal through jobstart"] = function()
	child.lua([[
		local commands = require("javascript-test-runner.commands")
		local api = require("javascript-test-runner.api")
		api.build_jest_invocation = function()
			return {
				command = "node",
				args = { "test.js" },
				cwd = vim.fn.getcwd(),
			}
		end
		vim.fn.jobstart = function(command, options)
			_G.started_command = command
			_G.started_options = options
			return 1
		end
		vim.cmd = function() end
		commands.run_jest("file")
	]])

	eq(child.lua_get([[_G.started_command]]), { "node", "test.js" })
	eq(child.lua_get([[_G.started_options.term]]), true)
	eq(child.lua_get([[_G.started_options.cwd]]), child.lua_get([[vim.fn.getcwd()]]))
end

return T
