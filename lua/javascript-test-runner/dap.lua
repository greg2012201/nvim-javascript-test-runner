local Module = {}

local configurations = {
	{ mode = "file", name = "Test File" },
	{ mode = "folder", name = "Test Folder" },
	{ mode = "line", name = "Test Line" },
}

local filetypes = {
	"javascript",
	"javascriptreact",
	"typescript",
	"typescriptreact",
}

local registration_key = "__javascript_test_runner_dap_mode"
local terminal_follow_config_key = "__javascript_test_runner_terminal_follow"
local terminal_follow_listener_key = "javascript-test-runner-terminal-follow"
local terminal_follow_session_key = "javascript-test-runner-terminal-follow"
local supported_adapter_types = {
	executable = true,
	pipe = true,
	server = true,
}
local terminal_follow_sessions = setmetatable({}, { __mode = "k" })

local function notify_error(message)
	vim.notify("javascript-test-runner: " .. message, vim.log.levels.ERROR)
end

local function adapter_is_supported(dap)
	if type(dap.adapters) ~= "table" then
		return false
	end

	local adapter = dap.adapters["pwa-node"]
	if type(adapter) == "function" then
		return true
	end

	return type(adapter) == "table" and supported_adapter_types[adapter.type] == true
end

local function absolute_path(path)
	local result = vim.fn.fnamemodify(path, ":p")
	if result ~= "/" then
		result = result:gsub("/+$", "")
	end
	return result
end

local function build_options(mode)
	local project = require("javascript-test-runner.project")
	local api = require("javascript-test-runner.api")
	local buffer = vim.api.nvim_get_current_buf()
	local buffer_name = vim.api.nvim_buf_get_name(buffer)
	local file = buffer_name ~= "" and absolute_path(buffer_name) or nil
	local folder = file and absolute_path(vim.fn.fnamemodify(file, ":h")) or absolute_path(vim.fn.getcwd())
	local context = project.detect(file or folder)

	if not context then
		return nil, "Could not find a project root containing package.json."
	end

	local options = {
		context = context,
		mode = mode,
	}

	if mode == "file" or mode == "line" then
		options.file = file
	elseif mode == "folder" then
		options.folder = folder
	end

	local environment, environment_error = project.resolve_environment(context, options)
	if not environment then
		return nil, environment_error
	end
	options.environment = environment

	if mode == "line" then
		local line_number = vim.api.nvim_win_get_cursor(0)[1]
		local line = vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""
		options.test_name = api.get_current_test_name_in_line(line)
	end

	return options
end

local function abort_configuration(dap, name)
	return {
		name = name,
		type = "pwa-node",
		request = "launch",
		program = function()
			return dap.ABORT
		end,
	}
end

local function follow_terminal_output(buffer, state)
	local scheduled = false

	local function move_to_bottom()
		scheduled = false
		if
			not state.active
			or not vim.api.nvim_buf_is_valid(buffer)
			or not vim.api.nvim_buf_is_loaded(buffer)
		then
			return
		end

		local line_count = vim.api.nvim_buf_line_count(buffer)
		for _, window in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buffer then
				vim.api.nvim_win_set_cursor(window, { line_count, 0 })
			end
		end
	end

	vim.api.nvim_buf_attach(buffer, false, {
		on_lines = function()
			if not state.active then
				return true
			end
			if scheduled then
				return
			end

			scheduled = true
			vim.schedule(move_to_bottom)
		end,
		on_detach = function()
			state.active = false
		end,
	})
	vim.schedule(move_to_bottom)
end

local function watch_terminal(session)
	if terminal_follow_sessions[session] then
		return
	end

	local state = { active = true }
	terminal_follow_sessions[session] = state

	local function stop()
		state.active = false
		terminal_follow_sessions[session] = nil
	end

	if type(session.on_close) == "table" then
		session.on_close[terminal_follow_session_key] = stop
	end

	local function attach_terminal()
		if not state.active then
			return
		end
		if session.closed then
			stop()
			return
		end

		local buffer = session.term_buf
		if
			type(buffer) == "number"
			and vim.api.nvim_buf_is_valid(buffer)
			and vim.api.nvim_buf_is_loaded(buffer)
		then
			follow_terminal_output(buffer, state)
			return
		end

		vim.defer_fn(attach_terminal, 50)
	end

	vim.schedule(attach_terminal)
end

local function register_terminal_follower(dap)
	dap.listeners = type(dap.listeners) == "table" and dap.listeners or {}
	dap.listeners.after = type(dap.listeners.after) == "table" and dap.listeners.after or {}
	dap.listeners.after.event_initialized = type(dap.listeners.after.event_initialized) == "table"
			and dap.listeners.after.event_initialized
		or {}
	dap.listeners.after.event_initialized[terminal_follow_listener_key] = function(session)
		if
			type(session) ~= "table"
			or type(session.config) ~= "table"
			or session.config[terminal_follow_config_key] ~= true
		then
			return
		end

		watch_terminal(session)
	end
end

local function resolve_configuration(dap, mode, name)
	local options, options_error = build_options(mode)
	if not options then
		notify_error(
			"Could not build the "
				.. mode
				.. " debug configuration: "
				.. tostring(options_error)
		)
		return abort_configuration(dap, name)
	end

	local result, error_message = require("javascript-test-runner.backends").build_debug_configuration(options)
	if type(result) ~= "table" then
		notify_error(
			"Could not build the "
				.. mode
				.. " debug configuration: "
				.. tostring(error_message or "the backend returned no configuration")
		)
		return abort_configuration(dap, name)
	end

	result.name = result.name or name
	if result.console == "integratedTerminal" then
		result[terminal_follow_config_key] = true
	end
	return result
end

local function make_configuration(dap, mode, name)
	local configuration = {
		name = name,
		type = "pwa-node",
		request = "launch",
		[registration_key] = mode,
	}

	return setmetatable(configuration, {
		__call = function()
			return resolve_configuration(dap, mode, name)
		end,
	})
end

local function contains_configuration(configurations_list, mode)
	for _, configuration in ipairs(configurations_list) do
		if type(configuration) == "table" and configuration[registration_key] == mode then
			return true
		end
	end

	return false
end

function Module.setup()
	local ok, dap = pcall(require, "dap")
	if not ok or type(dap) ~= "table" then
		notify_error("DAP integration requires nvim-dap. Install nvim-dap to enable it.")
		return false
	end

	if not adapter_is_supported(dap) then
		notify_error(
			"The pwa-node adapter is missing or unsupported. Configure a supported pwa-node adapter before enabling DAP integration."
		)
		return false
	end

	if type(dap.configurations) ~= "table" then
		notify_error("nvim-dap does not expose a valid configuration registry.")
		return false
	end

	for _, filetype in ipairs(filetypes) do
		local existing = dap.configurations[filetype]
		if existing ~= nil and type(existing) ~= "table" then
			notify_error("nvim-dap configurations for " .. filetype .. " must be a list.")
			return false
		end
	end

	register_terminal_follower(dap)

	local plugin_configurations = {}
	for _, definition in ipairs(configurations) do
		plugin_configurations[definition.mode] = make_configuration(dap, definition.mode, definition.name)
	end

	for _, filetype in ipairs(filetypes) do
		local filetype_configurations = dap.configurations[filetype]
		if not filetype_configurations then
			filetype_configurations = {}
			dap.configurations[filetype] = filetype_configurations
		end

		for _, definition in ipairs(configurations) do
			if not contains_configuration(filetype_configurations, definition.mode) then
				table.insert(filetype_configurations, plugin_configurations[definition.mode])
			end
		end
	end

	return true
end

return Module
