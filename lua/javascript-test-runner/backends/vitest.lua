local Module = {}
local Utils = require("javascript-test-runner.utils")

local escape_test_name = Utils.escape_test_name
local normalize_path = Utils.normalize_path
local resolve_path = Utils.resolve_path

local function append_target(args, options)
	if options.mode == "file" or options.mode == "line" then
		if type(options.file) ~= "string" or options.file == "" then
			return nil, "Vitest " .. options.mode .. " mode requires a file target"
		end
		args[#args + 1] = resolve_path(options.root, options.file)
	elseif options.mode == "folder" then
		if type(options.folder) ~= "string" or options.folder == "" then
			return nil, "Vitest folder mode requires a folder target"
		end
		args[#args + 1] = resolve_path(options.root, options.folder)
	end

	if options.mode == "line" then
		if type(options.test_name) ~= "string" or options.test_name == "" then
			return nil, "Vitest line mode requires a test name"
		end
		args[#args + 1] = "-t"
		args[#args + 1] = escape_test_name(options.test_name)
	end

	return args
end

function Module.build_invocation(options)
	if type(options) ~= "table" then
		return nil, "Vitest invocation options must be a table"
	end

	local valid_modes = {
		file = true,
		folder = true,
		project = true,
		line = true,
	}
	if not valid_modes[options.mode] then
		return nil, "Vitest mode is unsupported: " .. tostring(options.mode)
	end

	if type(options.context) ~= "table" or type(options.context.root) ~= "string" or options.context.root == "" then
		return nil, "Vitest invocation requires a project root"
	end

	local root = normalize_path(options.context.root)
	local environment = options.environment or {}
	if type(environment) ~= "table" then
		return nil, "Vitest invocation requires an environment table"
	end

	local local_script = root == "/" and "/node_modules/vitest/vitest.mjs" or root .. "/node_modules/vitest/vitest.mjs"
	local command
	local args = {}

	if vim.fn.filereadable(local_script) == 1 then
		if type(environment.node) ~= "string" or environment.node == "" then
			return nil, "Vitest requires a Node executable for the local Vitest script"
		end
		command = environment.node
		args[#args + 1] = local_script
	else
		if environment.package_manager ~= "npm" and environment.package_manager ~= "pnpm" then
			return nil, "Vitest fallback requires package_manager to be npm or pnpm"
		end
		command = environment.package_manager
		args[#args + 1] = "exec"
		if command == "npm" then
			args[#args + 1] = "--"
		end
		args[#args + 1] = "vitest"
	end

	args[#args + 1] = "run"
	local target_options = {
		mode = options.mode,
		file = options.file,
		folder = options.folder,
		test_name = options.test_name,
		root = root,
	}
	local target_args, error_message = append_target(args, target_options)
	if not target_args then
		return nil, error_message
	end

	return {
		command = command,
		args = target_args,
		cwd = root,
		env = environment.env or {},
	}
end

function Module.build_debug_configuration(options)
	local invocation, error_message = Module.build_invocation(options)
	if not invocation then
		return nil, error_message
	end

	local environment = options.environment or {}
	local local_script = invocation.cwd == "/" and "/node_modules/vitest/vitest.mjs"
		or invocation.cwd .. "/node_modules/vitest/vitest.mjs"
	if invocation.command ~= environment.node or invocation.args[1] ~= local_script then
		return nil, "Vitest DAP requires Node to launch a local Vitest script"
	end

	local args = {}
	for index = 2, #invocation.args do
		args[#args + 1] = invocation.args[index]
	end

	return {
		type = "pwa-node",
		request = "launch",
		runtimeExecutable = environment.node,
		program = local_script,
		args = args,
		cwd = invocation.cwd,
		env = environment.env or {},
	}
end

return Module
