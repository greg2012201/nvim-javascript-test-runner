local Module = {}

local modes = {
	file = true,
	folder = true,
	project = true,
	line = true,
}

local function notify_error(message)
	vim.notify(message, vim.log.levels.ERROR)
	return false
end

local function get_current_file()
	local buffer_name = vim.api.nvim_buf_get_name(0)
	if buffer_name == "" then
		return nil
	end

	return vim.fn.fnamemodify(buffer_name, ":p")
end

local function build_invocation(mode, options)
	local project = require("javascript-test-runner.project")
	local api = require("javascript-test-runner.api")
	local backends = require("javascript-test-runner.backends")
	local file = get_current_file()
	local path = file or vim.fn.getcwd()
	local context = options.context or project.detect(path)

	if not context then
		return nil, "Could not find a project root containing package.json."
	end

	local environment = project.resolve_environment(context)
	local invocation_options = {
		context = context,
		environment = environment,
		mode = mode,
	}

	if mode == "file" or mode == "line" then
		invocation_options.file = file
	elseif mode == "folder" then
		invocation_options.folder = file and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
	end

	if mode == "line" then
		invocation_options.test_name = api.get_current_test_name_in_line(vim.api.nvim_get_current_line())
	end

	return backends.build_invocation(invocation_options)
end

local function make_argv(invocation)
	if type(invocation) ~= "table" then
		return nil, "Could not build test invocation."
	end
	if type(invocation.command) ~= "string" or invocation.command == "" then
		return nil, "Test invocation does not contain a command."
	end
	if type(invocation.args) ~= "table" then
		return nil, "Test invocation does not contain an argument list."
	end

	local argv = { invocation.command }
	for _, argument in ipairs(invocation.args) do
		argv[#argv + 1] = argument
	end

	return argv
end

function Module.run(options)
	local mode = type(options) == "table" and options.mode or options
	if not modes[mode] then
		return notify_error("Invalid test mode: " .. tostring(mode) .. ". Use file, folder, project, or line.")
	end

	local invocation, invocation_error = build_invocation(mode, type(options) == "table" and options or {})
	if not invocation then
		return notify_error(invocation_error or "Could not build test invocation.")
	end

	local argv, argv_error = make_argv(invocation)
	if not argv then
		return notify_error(argv_error)
	end

	if type(invocation.env) ~= "table" then
		return notify_error("Test invocation does not contain an environment map.")
	end

	local terminal_options = {
		cwd = invocation.cwd,
		term = true,
	}
	if next(invocation.env) ~= nil then
		terminal_options.env = invocation.env
	end

	vim.cmd("vnew")

	local terminal_buffer = vim.api.nvim_get_current_buf()
	vim.bo[terminal_buffer].bufhidden = "hide"
	vim.bo[terminal_buffer].buflisted = true

	local ok, job_id = pcall(vim.fn.jobstart, argv, terminal_options)
	if not ok then
		vim.cmd("close")
		return notify_error("Could not start test process: " .. tostring(job_id))
	end
	if type(job_id) ~= "number" or job_id <= 0 then
		vim.cmd("close")
		return notify_error("Could not start test process.")
	end

	return true
end

return Module
