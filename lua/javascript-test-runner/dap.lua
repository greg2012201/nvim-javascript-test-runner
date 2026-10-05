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
local supported_adapter_types = {
	executable = true,
	pipe = true,
	server = true,
}

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
		environment = project.resolve_environment(context),
		mode = mode,
	}

	if mode == "file" or mode == "line" then
		options.file = file
	elseif mode == "folder" then
		options.folder = folder
	end

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
