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
		vim.fn.jobstart = function(command, options)
			vim.g.test_invocation = {
				argv = command,
				cwd = options.cwd,
				env = options.env or {},
				env_is_dict = options.env == nil or not vim.islist(options.env),
				term = options.term,
				terminal_buffer = vim.api.nvim_get_current_buf(),
			}
			return 1
		end
	]])
end

T["running tests"] = new_set()

T["running tests"]["runs a test file from its nearest project directory"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd.edit("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")
		_G.source_buffer = vim.api.nvim_get_current_buf()
	]])
	capture_invocation()
	child.cmd("Test file")

	eq(
		child.lua_get([[vim.g.test_invocation.cwd]]),
		absolute_path("tests/fixtures/project-discovery/monorepo/packages/widget")
	)
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
	eq(child.lua_get([[vim.g.test_invocation.terminal_buffer ~= _G.source_buffer]]), true)
	eq(child.lua_get([[vim.bo[vim.g.test_invocation.terminal_buffer].bufhidden]]), "hide")
	eq(child.lua_get([[vim.bo[vim.g.test_invocation.terminal_buffer].buflisted]]), true)

	child.lua([[vim.api.nvim_set_current_buf(_G.source_buffer)]])
	eq(child.lua_get([[vim.api.nvim_buf_is_valid(vim.g.test_invocation.terminal_buffer)]]), true)
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
		child.lua_get([[vim.g.test_invocation.cwd]]),
		absolute_path("tests/fixtures/project-discovery/independent/alpha")
	)
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
end

T["running tests"]["runs a Vitest project through the public command"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd.edit("tests/fixtures/pnpm-vitest/vitest.config.js")
	]])
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([[vim.g.test_invocation.argv]]), { "npm", "exec", "--", "vitest", "run" })
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), absolute_path("tests/fixtures/pnpm-vitest"))
	eq(child.lua_get([[vim.g.test_invocation.env]]), {})
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
end

return T
