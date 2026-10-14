local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local child = MiniTest.new_child_neovim()
local project_root = absolute_path("tests/.tmp-jest-esm")
local repository_root = absolute_path(".")
local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_case = function()
			child.lua(string.format(
				[[
					vim.cmd("cd " .. vim.fn.fnameescape(%q))
					vim.fn.delete(%q, "rf")
				]],
				repository_root,
				project_root
			))
		end,
		post_once = child.stop,
	},
})

local function run_test(options)
	local mode = options.mode or (options.extension and "file" or "project")
	local configuration = "{}"
	local sibling_extension = options.sibling_extension or ""
	if options.configured_node_options then
		configuration = string.format(
			"{ project_overrides = { [%q] = { env = { NODE_OPTIONS = %q } } } }",
			project_root,
			options.configured_node_options
		)
	end

	child.lua(string.format(
		[[
			local root = %q
			vim.fn.delete(root, "rf")
			vim.fn.mkdir(root .. "/src", "p")
			vim.fn.writefile({ %q }, root .. "/package.json")
			local file = root .. "/src/sample.test" .. %q
			vim.fn.writefile({ "test('sample', () => {})" }, file)
			local sibling_package_root = root .. "/" .. %q
			if %q ~= "" then
				vim.fn.mkdir(sibling_package_root, "p")
				vim.fn.writefile({ %q }, sibling_package_root .. "/package.json")
			end
			local sibling = root .. "/" .. %q .. "/" .. %q .. %q
			if %q ~= "" then
				vim.fn.mkdir(vim.fn.fnamemodify(sibling, ":h"), "p")
				vim.fn.writefile({ "test('sibling', () => {})" }, sibling)
			end
			vim.env.NODE_OPTIONS = %q
			require("javascript-test-runner").setup(%s)
			vim.cmd("cd " .. vim.fn.fnameescape(root))
			if %q == "project" then
				vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
			else
				vim.cmd("edit " .. vim.fn.fnameescape(file))
			end
			vim.fn.jobstart = function(command, job_options)
				vim.g.test_invocation = {
					argv = command,
					cwd = job_options.cwd,
					env = job_options.env or {},
					effective_node_options = (job_options.env or {}).NODE_OPTIONS or vim.env.NODE_OPTIONS or "",
				}
				return 1
			end
		]],
		project_root,
		options.package_json,
		options.extension or ".js",
		options.sibling_package_root or "",
		options.sibling_package_json or "",
		options.sibling_package_json or "",
		options.sibling_directory or "src",
		options.sibling_filename or "sibling.test",
		sibling_extension,
		sibling_extension,
		options.inherited_node_options,
		configuration,
		mode
	))

	child.cmd("Test " .. mode)

	return {
		argv = child.lua_get([[vim.g.test_invocation.argv]]),
		node_options = child.lua_get([[vim.g.test_invocation.effective_node_options]]),
		editor_node_options = child.lua_get([[vim.env.NODE_OPTIONS or ""]]),
	}
end

local function expect_node_options(node_options, preserved_options)
	eq(node_options:find("--experimental-vm-modules", 1, true) ~= nil, true)
	for option in preserved_options:gmatch("%S+") do
		eq(node_options:find(option, 1, true) ~= nil, true)
	end

	local count = 0
	local start = 1
	while true do
		local first, last = node_options:find("--experimental-vm-modules", start, true)
		if not first then
			break
		end
		count = count + 1
		start = last + 1
	end
	eq(count, 1)
end

T["Jest ESM runner"] = new_set()

T["Jest ESM runner"]["enables VM modules for a package with type module"] = function()
	local inherited = "--trace-warnings --max-old-space-size=4096"
	local result = run_test({
		package_json = '{"type":"module"}',
		inherited_node_options = inherited,
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["passes VM modules through a pnpm invocation"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = '{"type":"module","packageManager":"pnpm@10.0.0"}',
		inherited_node_options = inherited,
	})

	eq(result.argv[1], "pnpm")
	eq(result.argv[2], "exec")
	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["enables VM modules for ESM tests in the selected folder"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		inherited_node_options = inherited,
		mode = "folder",
		sibling_extension = ".mjs",
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["enables VM modules for ESM tests in the selected project"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		inherited_node_options = inherited,
		mode = "project",
		sibling_extension = ".mjs",
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["detects ESM files in Jest __tests__ directories"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		inherited_node_options = inherited,
		mode = "project",
		sibling_directory = "src/__tests__",
		sibling_filename = "example",
		sibling_extension = ".mjs",
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["detects ESM package scopes in a selected project"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		inherited_node_options = inherited,
		mode = "project",
		sibling_directory = "packages/widget/src",
		sibling_extension = ".js",
		sibling_package_root = "packages/widget",
		sibling_package_json = '{"type":"module"}',
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["ignores ESM test files under node_modules"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		inherited_node_options = inherited,
		mode = "project",
		sibling_directory = "node_modules",
		sibling_extension = ".mjs",
	})

	eq(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["enables VM modules for an mjs test file"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		extension = ".mjs",
		inherited_node_options = inherited,
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["enables VM modules for an mts test file"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		extension = ".mts",
		inherited_node_options = inherited,
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["does not duplicate an inherited VM modules flag"] = function()
	local inherited = "--trace-warnings --experimental-vm-modules"
	local result = run_test({
		package_json = '{"type":"module"}',
		inherited_node_options = inherited,
	})

	expect_node_options(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["preserves configured NODE_OPTIONS"] = function()
	local inherited = "--no-warnings"
	local configured = "--trace-deprecation --max-old-space-size=4096"
	local result = run_test({
		package_json = '{"type":"module"}',
		inherited_node_options = inherited,
		configured_node_options = configured,
	})

	expect_node_options(result.node_options, configured .. " " .. inherited)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["keeps configured NODE_OPTIONS as an override for CommonJS"] = function()
	local inherited = "--no-warnings"
	local configured = "--trace-deprecation"
	local result = run_test({
		package_json = "{}",
		extension = ".js",
		inherited_node_options = inherited,
		configured_node_options = configured,
	})

	eq(result.node_options, configured)
	eq(result.editor_node_options, inherited)
end

T["Jest ESM runner"]["does not add VM modules for a CommonJS test file"] = function()
	local inherited = "--trace-warnings"
	local result = run_test({
		package_json = "{}",
		extension = ".js",
		inherited_node_options = inherited,
	})

	eq(result.node_options, inherited)
	eq(result.editor_node_options, inherited)
end

return T
