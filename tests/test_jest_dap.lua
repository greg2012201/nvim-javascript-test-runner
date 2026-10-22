local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local temporary_root = absolute_path("tests/.tmp-jest-dap")

local function clear_temporary_root()
	vim.fn.delete(temporary_root, "rf")
end

local function create_project(root)
	root = root or temporary_root .. "/project"
	vim.fn.mkdir(root, "p")

	local context = {
		root = root,
		package_json = root .. "/package.json",
	}
	vim.fn.writefile({ "{}" }, context.package_json)

	return context
end

local function create_jest_script(root)
	local script = root .. "/node_modules/jest/bin/jest.js"
	vim.fn.mkdir(vim.fn.fnamemodify(script, ":h"), "p")
	vim.fn.writefile({ "" }, script)
	return script
end

local function create_local_jest_script(context)
	return create_jest_script(context.root)
end

local function create_target(context, relative_path)
	local path = context.root .. "/" .. relative_path
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ "" }, path)
	return path
end

local function options_for(context, mode)
	return {
		context = context,
		environment = {
			node = "/opt/node/bin/node",
			package_manager = "npm",
			framework = "jest",
		},
		mode = mode,
	}
end

local function build_debug_configuration(options)
	return require("javascript-test-runner.backends.jest").build_debug_configuration(options)
end

local T = new_set({
	hooks = {
		pre_case = clear_temporary_root,
		post_case = clear_temporary_root,
	},
})

T["Jest DAP configuration"] = new_set()

T["Jest DAP configuration"]["builds a file launch configuration using local Jest"] = function()
	local context = create_project()
	local script = create_local_jest_script(context)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "file")
	options.file = file
	options.environment.env = { TEST_MODE = "dap" }

	eq(build_debug_configuration(options), {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = "/opt/node/bin/node",
		program = script,
		cwd = context.root,
		env = { TEST_MODE = "dap" },
		args = {
			"--runInBand",
			"--runTestsByPath",
			file,
		},
	})
end

T["Jest DAP configuration"]["finds Jest hoisted to a workspace root"] = function()
	local workspace_root = temporary_root .. "/workspace"
	local context = create_project(workspace_root .. "/packages/app")
	local script = create_jest_script(workspace_root)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "file")
	options.file = file

	eq(build_debug_configuration(options), {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = "/opt/node/bin/node",
		program = script,
		cwd = context.root,
		env = {},
		args = {
			"--runInBand",
			"--runTestsByPath",
			file,
		},
	})
end

T["Jest DAP configuration"]["builds a folder launch configuration with an absolute target"] = function()
	local context = create_project()
	local script = create_local_jest_script(context)
	local folder = context.root .. "/src/unit"
	vim.fn.mkdir(folder, "p")
	create_target(context, "src/unit/example.test.js")
	local options = options_for(context, "folder")
	options.folder = folder

	eq(build_debug_configuration(options), {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = "/opt/node/bin/node",
		program = script,
		cwd = context.root,
		env = {},
		args = {
			"--runInBand",
			folder,
		},
	})
end

T["Jest DAP configuration"]["builds a line launch configuration with an escaped literal name and absolute file"] = function()
	local context = create_project()
	local script = create_local_jest_script(context)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "line")
	options.file = file
	options.test_name = "renders (empty) [v1].+-beta"

	eq(build_debug_configuration(options), {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = "/opt/node/bin/node",
		program = script,
		cwd = context.root,
		env = {},
		args = {
			"--runInBand",
			"--runTestsByPath",
			file,
			"-t",
			[[renders \(empty\) \[v1\]\.\+-beta]],
		},
	})
end

return T
