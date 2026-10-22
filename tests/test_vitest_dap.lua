local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local temporary_root = absolute_path("tests/.tmp-vitest-dap")

local function clear_temporary_root()
	vim.fn.delete(temporary_root, "rf")
end

local function create_project(root, script_root)
	root = root or temporary_root .. "/project"
	local context = {
		root = root,
		package_json = root .. "/package.json",
	}

	vim.fn.mkdir(root, "p")
	vim.fn.writefile({ "{}" }, context.package_json)

	script_root = script_root or root
	local script = script_root .. "/node_modules/vitest/vitest.mjs"
	vim.fn.mkdir(vim.fn.fnamemodify(script, ":h"), "p")
	vim.fn.writefile({ "" }, script)

	return context, script
end

local function create_target(options)
	local path = options.context.root .. "/" .. options.relative_path
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ "" }, path)
	return path
end

local function options_for(options)
	return {
		context = options.context,
		environment = {
			node = "/opt/node/bin/node",
			package_manager = "npm",
			framework = "vitest",
			env = options.env,
		},
		mode = options.mode,
	}
end

local function build_debug_configuration(options)
	return require("javascript-test-runner.backends.vitest").build_debug_configuration(options)
end

local function expected_configuration(options)
	return {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = "/opt/node/bin/node",
		program = options.script,
		args = options.args,
		cwd = options.context.root,
		env = options.env or {},
	}
end

local T = new_set({
	hooks = {
		pre_case = clear_temporary_root,
		post_case = clear_temporary_root,
	},
})

T["Vitest DAP configuration"] = new_set()

T["Vitest DAP configuration"]["builds a current-file launch configuration"] = function()
	local context, script = create_project()
	local file = create_target({
		context = context,
		relative_path = "src/example.test.js",
	})
	local env = {
		NODE_ENV = "test",
	}
	local options = options_for({
		context = context,
		mode = "file",
		env = env,
	})
	options.file = file

	eq(
		build_debug_configuration(options),
		expected_configuration({
			context = context,
			script = script,
			args = { "run", file },
			env = env,
		})
	)
end

T["Vitest DAP configuration"]["finds Vitest hoisted to a workspace root"] = function()
	local workspace_root = temporary_root .. "/workspace"
	local context, script = create_project(workspace_root .. "/packages/app", workspace_root)
	local file = create_target({
		context = context,
		relative_path = "src/example.test.js",
	})
	local options = options_for({
		context = context,
		mode = "file",
	})
	options.file = file

	eq(
		build_debug_configuration(options),
		expected_configuration({
			context = context,
			script = script,
			args = { "run", file },
		})
	)
end

T["Vitest DAP configuration"]["builds a current-folder launch configuration"] = function()
	local context, script = create_project()
	local folder = context.root .. "/src/components"
	vim.fn.mkdir(folder, "p")
	local options = options_for({
		context = context,
		mode = "folder",
	})
	options.folder = folder

	eq(
		build_debug_configuration(options),
		expected_configuration({
			context = context,
			script = script,
			args = { "run", folder },
		})
	)
end

T["Vitest DAP configuration"]["builds a current-line launch configuration with an escaped test name"] = function()
	local context, script = create_project()
	local file = create_target({
		context = context,
		relative_path = "src/example.test.js",
	})
	local options = options_for({
		context = context,
		mode = "line",
	})
	options.file = file
	options.test_name = "matches (a+b). [draft]? - v1"

	eq(
		build_debug_configuration(options),
		expected_configuration({
			context = context,
			script = script,
			args = {
				"run",
				file,
				"-t",
				[[matches \(a\+b\)\. \[draft\]\? - v1]],
			},
		})
	)
end

return T
