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

local function activate_nvm(invocation)
	local nvm_dir = vim.env.NVM_DIR
	if type(nvm_dir) ~= "string" or nvm_dir == "" then
		nvm_dir = vim.fn.expand("~") .. "/.nvm"
	end
	if vim.fn.filereadable(nvm_dir .. "/nvm.sh") ~= 1 or vim.fn.executable("bash") ~= 1 then
		return invocation
	end

	local args = {
		"--noprofile",
		"--norc",
		"-c",
		'export NVM_DIR="$1"; source "$NVM_DIR/nvm.sh" >/dev/null && nvm use >/dev/null && shift && exec "$@"',
		"javascript-test-runner",
		nvm_dir,
		invocation.command,
	}
	vim.list_extend(args, invocation.args)
	invocation.command = "bash"
	invocation.args = args
	return invocation
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

	local invocation_options = {
		context = context,
		mode = mode,
	}

	if mode == "file" or mode == "line" then
		invocation_options.file = file
	elseif mode == "folder" then
		invocation_options.folder = file and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
	end

	local environment, environment_error = project.resolve_environment(context, invocation_options)
	if not environment then
		return nil, environment_error
	end
	invocation_options.environment = environment

	if mode == "line" then
		invocation_options.test_name = api.get_current_test_name_in_line(vim.api.nvim_get_current_line())
	end

	local invocation, invocation_error = backends.build_invocation(invocation_options)
	if not invocation then
		return nil, invocation_error
	end

	if environment.node_source == ".nvmrc" then
		return activate_nvm(invocation)
	end

	return invocation
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

	local terminal_buffer
	local terminal_window
	local terminal_options = {
		cwd = invocation.cwd,
		term = true,
		on_exit = function()
			vim.schedule(function()
				if not vim.api.nvim_win_is_valid(terminal_window) then
					return
				end
				if vim.api.nvim_get_current_win() ~= terminal_window then
					return
				end
				if vim.api.nvim_win_get_buf(terminal_window) ~= terminal_buffer then
					return
				end
				vim.cmd("stopinsert")
			end)
		end,
	}
	if next(invocation.env) ~= nil then
		terminal_options.env = invocation.env
	end

	vim.cmd("vnew")

	terminal_buffer = vim.api.nvim_get_current_buf()
	terminal_window = vim.api.nvim_get_current_win()
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

	vim.cmd("startinsert")

	return true
end

return Module
