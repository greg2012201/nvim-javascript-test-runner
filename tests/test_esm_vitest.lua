local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local root = absolute_path("tests/.tmp-vitest-esm")
local child = MiniTest.new_child_neovim()

local function clear_project()
	vim.fn.delete(root, "rf")
end

local function create_project()
	vim.fn.mkdir(root .. "/src", "p")
	vim.fn.writefile({
		'{"type":"module","devDependencies":{"vitest":"^3.0.0"}}',
	}, root .. "/package.json")
	local file = root .. "/src/example.test.mjs"
	vim.fn.writefile({ "test('example', () => {})" }, file)
	return file
end

local function capture_invocation()
	child.lua([[
		vim.fn.jobstart = function(command, options)
			vim.g.test_invocation = {
				argv = command,
				cwd = options.cwd,
				env = options.env or {},
			}
			return 1
		end
	]])
end

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			clear_project()
		end,
		post_case = clear_project,
		post_once = child.stop,
	},
})

T["Vitest ESM isolation"] = new_set()

T["Vitest ESM isolation"]["does not add the Jest ESM flag to the public invocation"] = function()
	local file = create_project()

	child.lua(string.format(
		[[
			require("javascript-test-runner").setup()
			vim.cmd.edit(%q)
		]],
		file
	))
	capture_invocation()
	child.cmd("Test file")

	local invocation = child.lua_get([[vim.g.test_invocation]])
	local flag = "--experimental-vm-modules"

	eq(invocation.argv[4], "vitest")
	eq(invocation.cwd, root)
	eq(table.concat(invocation.argv, " "):find(flag, 1, true), nil)
	eq((invocation.env.NODE_OPTIONS or ""):find(flag, 1, true), nil)
end

return T
