local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local temporary_root = absolute_path("tests/.tmp-esm-dap")
local child = MiniTest.new_child_neovim()

local function clear_temporary_root()
	vim.fn.delete(temporary_root, "rf")
end

local function create_project()
	local root = temporary_root .. "/project"
	local script = root .. "/node_modules/jest/bin/jest.js"
	local file = root .. "/src/example.test.js"

	vim.fn.mkdir(vim.fn.fnamemodify(script, ":h"), "p")
	vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
	vim.fn.writefile({ '{"type":"module","devDependencies":{"jest":"^30.0.0"}}' }, root .. "/package.json")
	vim.fn.writefile({ "" }, script)
	vim.fn.writefile({ "" }, file)

	return file
end

local T = new_set({
	hooks = {
		pre_case = function()
			clear_temporary_root()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_case = clear_temporary_root,
		post_once = child.stop,
	},
})

T["Jest ESM DAP configuration"] = new_set()

T["Jest ESM DAP configuration"]["passes the ESM runtime flag to Jest without changing Neovim's environment"] = function()
	local file = create_project()

	child.lua(string.format(
		[[
			vim.env.NODE_OPTIONS = nil
			vim.cmd.edit(%q)
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
			}
			package.loaded["dap"] = dap
			require("javascript-test-runner").setup({ dap = true })
			_G.esm_launch_configuration = dap.configurations.javascript[1]()
		]],
		file
	))

	local launch_configuration = child.lua_get([[_G.esm_launch_configuration]])

	eq(child.lua_get([[vim.env.NODE_OPTIONS]]), vim.NIL)
	eq(launch_configuration.env.NODE_OPTIONS, "--experimental-vm-modules")
end

return T
