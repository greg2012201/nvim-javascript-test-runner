local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local fixture_root = absolute_path("tests/.backend-dispatch-fixtures")

local function write_file(path, contents)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(contents, path)
end

local function project_fixture(name, backend_path)
	local root = fixture_root .. "/" .. name
	local file = root .. "/src/example.test.js"

	write_file(root .. "/package.json", { vim.fn.json_encode({ name = name }) })
	write_file(root .. "/" .. backend_path, { "" })
	write_file(file, { "describe('example', () => {})" })

	return {
		context = {
			root = root,
			package_json = root .. "/package.json",
		},
		file = file,
	}
end

local function build_invocation(options)
	return require("javascript-test-runner.backends").build_invocation(options)
end

local T = new_set({
	hooks = {
		pre_case = function()
			vim.fn.delete(fixture_root, "rf")
			vim.fn.mkdir(fixture_root, "p")
		end,
		post_once = function()
			vim.fn.delete(fixture_root, "rf")
		end,
	},
})

T["backend dispatch"] = new_set()

T["backend dispatch"]["dispatches Jest projects and returns a normalized invocation"] = function()
	local project = project_fixture("jest", "node_modules/jest/bin/jest.js")
	local invocation, err = build_invocation({
		context = project.context,
		environment = {
			node = "node",
			package_manager = "npm",
			framework = "jest",
		},
		mode = "project",
	})

	eq(err, nil)
	eq(invocation, {
		command = "node",
		args = {
			project.context.root .. "/node_modules/jest/bin/jest.js",
			"--runInBand",
		},
		cwd = project.context.root,
		env = {},
	})
end

T["backend dispatch"]["dispatches Vitest projects to Vitest behavior"] = function()
	local project = project_fixture("vitest", "node_modules/vitest/vitest.mjs")
	local invocation, err = build_invocation({
		context = project.context,
		environment = {
			node = "node",
			package_manager = "npm",
			framework = "vitest",
		},
		mode = "project",
	})

	eq(err, nil)
	eq(invocation, {
		command = "node",
		args = {
			project.context.root .. "/node_modules/vitest/vitest.mjs",
			"run",
		},
		cwd = project.context.root,
		env = {},
	})
end

T["backend dispatch"]["reports an error for an unsupported framework"] = function()
	local project = project_fixture("unsupported", "node_modules/mocha/bin/mocha.js")
	local invocation, err = build_invocation({
		context = project.context,
		environment = {
			node = "node",
			package_manager = "npm",
			framework = "mocha",
		},
		mode = "project",
	})

	eq(invocation, nil)
	eq(type(err), "string")
	local message = err:lower()
	eq(message:find("mocha", 1, true) ~= nil, true)
	eq(message:find("unsupported", 1, true) ~= nil or message:find("not supported", 1, true) ~= nil, true)
end

return T
