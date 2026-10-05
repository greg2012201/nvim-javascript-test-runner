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

T["command execution"]["delegates run options to the generic runner and preserves its result"] = function()
	child.lua([[
		local commands = require("javascript-test-runner.commands")
	package.loaded["javascript-test-runner.runner"] = {
		run = function(options)
			_G.runner_options = options
			return "runner result"
		end,
	}
	_G.command_result = commands.run("project")
	]])

	eq(child.lua_get([[_G.runner_options]]), "project")
	eq(child.lua_get([[_G.command_result]]), "runner result")
end

return T
