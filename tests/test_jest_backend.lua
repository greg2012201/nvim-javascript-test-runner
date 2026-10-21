local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local temporary_root = absolute_path("tests/.tmp-jest-backend")

local function clear_temporary_root()
	vim.fn.delete(temporary_root, "rf")
end

local function create_project()
	local root = temporary_root .. "/project"
	vim.fn.mkdir(root, "p")

	local context = {
		root = root,
		package_json = root .. "/package.json",
	}
	vim.fn.writefile({ "{}" }, context.package_json)

	return context
end

local function create_local_jest_script(context)
	local script = context.root .. "/node_modules/jest/bin/jest.js"
	vim.fn.mkdir(vim.fn.fnamemodify(script, ":h"), "p")
	vim.fn.writefile({ "" }, script)
end

local function create_target(context, relative_path)
	local path = context.root .. "/" .. relative_path
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ "" }, path)
	return path
end

local function options_for(context, mode, package_manager)
	return {
		context = context,
		environment = {
			node = "/opt/node/bin/node",
			package_manager = package_manager or "npm",
			framework = "jest",
		},
		mode = mode,
	}
end

local function build_invocation(options)
	return require("javascript-test-runner.backends.jest").build_invocation(options)
end

local T = new_set({
	hooks = {
		pre_case = clear_temporary_root,
		post_case = clear_temporary_root,
	},
})

T["Jest backend invocation"] = new_set()

T["Jest backend invocation"]["builds a file invocation with the local Jest script and Node executable"] = function()
	local context = create_project()
	create_local_jest_script(context)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "file")
	options.file = file

	eq(build_invocation(options), {
		command = "/opt/node/bin/node",
		args = {
			context.root .. "/node_modules/jest/bin/jest.js",
			"--runInBand",
			"--runTestsByPath",
			file,
		},
		cwd = context.root,
		env = {},
	})
end

T["Jest backend invocation"]["builds a folder invocation using an absolute folder path"] = function()
	local context = create_project()
	create_local_jest_script(context)
	local folder = context.root .. "/src/unit"
	create_target(context, "src/unit/example.test.js")
	local options = options_for(context, "folder")
	options.folder = folder

	eq(build_invocation(options), {
		command = "/opt/node/bin/node",
		args = {
			context.root .. "/node_modules/jest/bin/jest.js",
			"--runInBand",
			folder,
		},
		cwd = context.root,
		env = {},
	})
end

T["Jest backend invocation"]["builds a project invocation from the project root"] = function()
	local context = create_project()
	create_local_jest_script(context)

	eq(build_invocation(options_for(context, "project")), {
		command = "/opt/node/bin/node",
		args = {
			context.root .. "/node_modules/jest/bin/jest.js",
			"--runInBand",
		},
		cwd = context.root,
		env = {},
	})
end

T["Jest backend invocation"]["builds a line invocation for an absolute file path and test name"] = function()
	local context = create_project()
	create_local_jest_script(context)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "line")
	options.file = file
	options.test_name = "renders the page"

	eq(build_invocation(options), {
		command = "/opt/node/bin/node",
		args = {
			context.root .. "/node_modules/jest/bin/jest.js",
			"--runInBand",
			"--runTestsByPath",
			file,
			"-t",
			"renders the page",
		},
		cwd = context.root,
		env = {},
	})
end

T["Jest backend invocation"]["escapes test-name regex metacharacters for literal matching"] = function()
	local context = create_project()
	create_local_jest_script(context)
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "line")
	options.file = file
	options.test_name = "matches (a+b). [draft]? - v1"

	local invocation = build_invocation(options)

	eq(invocation.args[#invocation.args], "matches \\(a\\+b\\)\\. \\[draft\\]\\? - v1")
end

T["Jest backend invocation"]["uses npm exec with Jest when no local installation exists"] = function()
	local context = create_project()
	local file = create_target(context, "src/example.test.js")
	local options = options_for(context, "file", "npm")
	options.environment.env = { PATH = "/existing/bin" }
	options.file = file

	eq(build_invocation(options), {
		command = "npm",
		args = {
			"exec",
			"--",
			"jest",
			"--runInBand",
			"--runTestsByPath",
			file,
		},
		cwd = context.root,
		env = {
			PATH = "/opt/node/bin" .. package.config:sub(3, 3) .. "/existing/bin",
		},
	})
end

T["Jest backend invocation"]["uses pnpm exec with Jest when no local installation exists"] = function()
	local context = create_project()
	local options = options_for(context, "project", "pnpm")
	options.environment.env = { PATH = "/existing/bin" }

	eq(build_invocation(options), {
		command = "pnpm",
		args = {
			"exec",
			"jest",
			"--runInBand",
		},
		cwd = context.root,
		env = {
			PATH = "/opt/node/bin" .. package.config:sub(3, 3) .. "/existing/bin",
		},
	})
end

T["Jest backend invocation"]["reports a missing file target"] = function()
	local context = create_project()
	create_local_jest_script(context)
	local invocation, err = build_invocation(options_for(context, "file"))

	eq(invocation, nil)
	eq(type(err), "string")
	eq(err ~= "", true)
end

T["Jest backend invocation"]["rejects unsupported modes"] = function()
	local context = create_project()
	local invocation, err = build_invocation(options_for(context, "suite"))

	eq(invocation, nil)
	eq(type(err), "string")
	eq(err ~= "", true)
end

return T
