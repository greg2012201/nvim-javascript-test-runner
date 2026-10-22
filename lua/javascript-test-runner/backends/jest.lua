local Module = {}
local Utils = require("javascript-test-runner.utils")

local escape_test_name = Utils.escape_test_name
local normalize_path = Utils.normalize_path
local resolve_path = Utils.resolve_path

local function add_target_arguments(config)
	local args = config.args
	local options = config.options
	local root = config.root

	if options.mode == "file" or options.mode == "line" then
		if type(options.file) ~= "string" or options.file == "" then
			return nil, "Jest " .. options.mode .. " mode requires a file target"
		end

		local file = resolve_path(root, options.file)
		if vim.fn.filereadable(file) ~= 1 then
			return nil, "Jest file target is not readable: " .. file
		end

		table.insert(args, "--runTestsByPath")
		table.insert(args, file)

		if options.mode == "line" then
			if type(options.test_name) ~= "string" or options.test_name == "" then
				return nil, "Jest line mode requires a test name"
			end

			table.insert(args, "-t")
			table.insert(args, escape_test_name(options.test_name))
		end
	elseif options.mode == "folder" then
		if type(options.folder) ~= "string" or options.folder == "" then
			return nil, "Jest folder mode requires a folder target"
		end

		local folder = resolve_path(root, options.folder)
		if vim.fn.isdirectory(folder) ~= 1 then
			return nil, "Jest folder target is not a directory: " .. folder
		end

		table.insert(args, folder)
	end

	return args
end

local function find_local_jest_script(root)
	local current_dir = root
	while true do
		local script = current_dir == "/" and "/node_modules/jest/bin/jest.js"
			or current_dir .. "/node_modules/jest/bin/jest.js"
		if vim.fn.filereadable(script) == 1 then
			return script
		end

		local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
		if parent_dir == current_dir then
			return nil
		end
		current_dir = parent_dir
	end
end

local function invocation(options, root)
	local environment = options.environment
	local local_script = find_local_jest_script(root)
	local args
	local command
	local env = environment.env or {}

	if local_script then
		if type(environment.node) ~= "string" or environment.node == "" then
			return nil, "Jest requires a Node executable for the local installation"
		end

		command = environment.node
		args = { local_script, "--runInBand" }
	else
		if environment.package_manager ~= "npm" and environment.package_manager ~= "pnpm" then
			return nil, "Jest requires npm or pnpm when no local installation is available"
		end

		command = environment.package_manager
		if command == "npm" then
			args = { "exec", "--", "jest", "--runInBand" }
		else
			args = { "exec", "jest", "--runInBand" }
		end
		if type(env) == "table" then
			env = Utils.environment_with_node_path(environment)
		end
	end

	local target_args, target_error = add_target_arguments({
		args = args,
		options = options,
		root = root,
	})
	if not target_args then
		return nil, target_error
	end

	return {
		command = command,
		args = target_args,
		cwd = root,
		env = env,
	}
end

function Module.build_invocation(options)
	if type(options) ~= "table" then
		return nil, "Jest invocation options must be a table"
	end

	if options.mode ~= "file" and options.mode ~= "folder" and options.mode ~= "project" and options.mode ~= "line" then
		return nil, "Unsupported Jest invocation mode: " .. tostring(options.mode)
	end

	if type(options.context) ~= "table" or type(options.context.root) ~= "string" or options.context.root == "" then
		return nil, "Jest invocation requires a project root"
	end

	if type(options.environment) ~= "table" then
		return nil, "Jest invocation requires an environment"
	end

	local root = normalize_path(options.context.root)
	if vim.fn.isdirectory(root) ~= 1 then
		return nil, "Jest project root is not a directory: " .. root
	end

	return invocation(options, root)
end

function Module.build_debug_configuration(options)
	local built_invocation, invocation_error = Module.build_invocation(options)
	if not built_invocation then
		return nil, invocation_error
	end

	local environment = options.environment
	local local_script = find_local_jest_script(built_invocation.cwd)
	if
		not local_script
		or built_invocation.command ~= environment.node
		or built_invocation.args[1] ~= local_script
	then
		return nil, "Jest DAP requires a local Jest script and cannot use the npm or pnpm fallback"
	end

	local args = {}
	for index = 2, #built_invocation.args do
		table.insert(args, built_invocation.args[index])
	end

	return {
		type = "pwa-node",
		request = "launch",
		console = "integratedTerminal",
		runtimeExecutable = environment.node,
		program = built_invocation.args[1],
		args = args,
		cwd = built_invocation.cwd,
		env = environment.env or {},
	}
end

return Module
