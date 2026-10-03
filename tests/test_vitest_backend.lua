local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local root = absolute_path("tests/.vitest-backend-fixture")
local package_json = root .. "/package.json"
local script = root .. "/node_modules/vitest/vitest.mjs"

local function write_file(path, lines)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(lines, path)
end

local function reset_project()
	vim.fn.delete(root, "rf")
	vim.fn.mkdir(root, "p")
	write_file(package_json, { "{}" })
end

local function build_invocation(options)
	options.context = {
		root = root,
		package_json = package_json,
	}
	options.environment = options.environment or {
		node = "/test/node",
		package_manager = "npm",
	}
	return require("javascript-test-runner.backends.vitest").build_invocation(options)
end

local function expect_invocation(options)
	eq(options.invocation.command, options.command)
	eq(options.invocation.args, options.args)
	eq(options.invocation.cwd, root)
	eq(options.invocation.env, {})
end

local function expect_error(options)
	local invocation, error_message = build_invocation(options)
	eq(invocation, nil)
	eq(type(error_message), "string")
end

local T = new_set({
	hooks = {
		pre_case = reset_project,
		post_case = function()
			vim.fn.delete(root, "rf")
		end,
	},
})

T["Vitest invocation"] = new_set()

T["Vitest invocation"]["runs a file through the npm fallback with an absolute path"] = function()
	write_file(root .. "/src/example.test.js", { "test('example', () => {})" })

	local invocation = build_invocation({
		mode = "file",
		file = "src/example.test.js",
	})

	expect_invocation({
		invocation = invocation,
		command = "npm",
		args = {
			"exec",
			"--",
			"vitest",
			"run",
			root .. "/src/example.test.js",
		},
	})
end

T["Vitest invocation"]["runs a folder through the pnpm fallback"] = function()
	vim.fn.mkdir(root .. "/src/components", "p")

	local invocation = build_invocation({
		mode = "folder",
		folder = "src/components",
		environment = {
			node = "/test/node",
			package_manager = "pnpm",
		},
	})

	expect_invocation({
		invocation = invocation,
		command = "pnpm",
		args = {
			"exec",
			"vitest",
			"run",
			root .. "/src/components",
		},
	})
end

T["Vitest invocation"]["runs the project through the local script with the selected Node executable"] = function()
	write_file(script, { "" })

	local invocation = build_invocation({
		mode = "project",
		environment = {
			node = "/custom/node",
			package_manager = "pnpm",
		},
	})

	expect_invocation({
		invocation = invocation,
		command = "/custom/node",
		args = {
			script,
			"run",
		},
	})
end

T["Vitest invocation"]["selects a line test by its escaped name and absolute file path"] = function()
	write_file(root .. "/src/example.test.js", { "it('renders (empty) [v1].+-beta', () => {})" })
	write_file(script, { "" })

	local invocation = build_invocation({
		mode = "line",
		file = "src/example.test.js",
		test_name = "renders (empty) [v1].+-beta",
	})

	expect_invocation({
		invocation = invocation,
		command = "/test/node",
		args = {
			script,
			"run",
			root .. "/src/example.test.js",
			"-t",
			[[renders \(empty\) \[v1\]\.\+-beta]],
		},
	})
end

T["Vitest invocation"]["returns an error when file mode has no file target"] = function()
	expect_error({ mode = "file" })
end

T["Vitest invocation"]["returns an error when folder mode has no folder target"] = function()
	expect_error({ mode = "folder" })
end

T["Vitest invocation"]["returns an error when line mode has no file target"] = function()
	expect_error({
		mode = "line",
		test_name = "example",
	})
end

T["Vitest invocation"]["returns an error when line mode has no test name"] = function()
	expect_error({
		mode = "line",
		file = "src/example.test.js",
	})
end

T["Vitest invocation"]["returns an error for unsupported modes"] = function()
	expect_error({ mode = "watch" })
end

return T
