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

local function capture_invocation()
	child.lua([[
		vim.fn.jobstart = function(_, options)
			vim.g.test_invocation_cwd = options.cwd
			vim.g.test_invocation_term = options.term
			return 1
		end
	]])
end

T["running tests"] = new_set()

T["running tests"]["runs a test file from its nearest project directory"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd.edit("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")
	]])
	capture_invocation()
	child.cmd("Test file")

	eq(
		child.lua_get([[vim.g.test_invocation_cwd]]),
		absolute_path("tests/fixtures/project-discovery/monorepo/packages/widget")
	)
	eq(child.lua_get([[vim.g.test_invocation_term]]), true)
end

T["running tests"]["uses the working directory for an unnamed project run"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd("cd tests/fixtures/project-discovery/independent/alpha/src")
		vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	]])
	capture_invocation()
	child.cmd("Test project")

	eq(
		child.lua_get([[vim.g.test_invocation_cwd]]),
		absolute_path("tests/fixtures/project-discovery/independent/alpha")
	)
	eq(child.lua_get([[vim.g.test_invocation_term]]), true)
end

return T
