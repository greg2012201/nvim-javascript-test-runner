local Module = {}

local defaults = {
	command_name = "Test",
	keymaps = {
		file = "<Leader>tf",
		line = "<Leader>tl",
	},
	dap = false,
	project_overrides = {},
}

local config

local function copy(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, item in pairs(value) do
		result[key] = copy(item)
	end
	return result
end

local function invalid_config(field, expectation)
	error(("Invalid configuration field '%s': %s"):format(field, expectation), 3)
end

local function validate_environment(environment, field)
	if type(environment) ~= "table" then
		invalid_config(field, "expected a table")
	end

	for name, value in pairs(environment) do
		local variable_field = field .. "[" .. tostring(name) .. "]"
		if type(name) ~= "string" or name == "" or name:find("[%z=]") then
			invalid_config(field, "environment variable names must be non-empty strings")
		end
		if type(value) ~= "string" or value:find("%z") then
			invalid_config(variable_field, "expected a string value")
		end
	end
end

local function validate_project_overrides(overrides)
	if type(overrides) ~= "table" then
		invalid_config("project_overrides", "expected a table")
	end

	local supported_fields = {
		package_manager = true,
		framework = true,
		node_version = true,
		env = true,
	}

	for path, project_options in pairs(overrides) do
		local project_field = "project_overrides[" .. tostring(path) .. "]"
		if type(path) ~= "string" or path == "" or path:find("%z") then
			invalid_config("project_overrides", "project paths must be non-empty strings")
		end
		if type(project_options) ~= "table" then
			invalid_config(project_field, "expected a table")
		end

		for key, value in pairs(project_options) do
			local field = project_field .. "." .. tostring(key)
			if type(key) ~= "string" or not supported_fields[key] then
				invalid_config(field, "unsupported project override")
			end
			if key == "package_manager" and value ~= "npm" and value ~= "pnpm" then
				invalid_config(field, "expected 'npm' or 'pnpm'")
			elseif key == "framework" and value ~= "jest" and value ~= "vitest" then
				invalid_config(field, "expected 'jest' or 'vitest'")
			elseif key == "node_version"
				and (type(value) ~= "string" or value == "" or not value:match("^[%w._+/*%-]+$"))
			then
				invalid_config(field, "expected a version understood by a Node.js version manager")
			elseif key == "env" then
				validate_environment(value, field)
			end
		end
	end
end

local function validate_options(opts)
	if opts == nil then
		return
	end
	if type(opts) ~= "table" then
		invalid_config("options", "expected a table")
	end

	local supported_fields = {
		command_name = true,
		keymaps = true,
		dap = true,
		project_overrides = true,
	}
	for key in pairs(opts) do
		if type(key) ~= "string" or not supported_fields[key] then
			invalid_config(tostring(key), "unsupported setup option")
		end
	end

	if opts.command_name ~= nil
		and (
			type(opts.command_name) ~= "string"
			or not opts.command_name:match("^[A-Z][A-Za-z0-9]*$")
		)
	then
		invalid_config("command_name", "expected a non-empty valid command name")
	end

	if opts.keymaps ~= nil then
		if type(opts.keymaps) ~= "table" then
			invalid_config("keymaps", "expected a table")
		end
		for key, value in pairs(opts.keymaps) do
			local field = "keymaps." .. tostring(key)
			if key ~= "file" and key ~= "line" then
				invalid_config(field, "unsupported keymap")
			end
			if value ~= false and (type(value) ~= "string" or value == "") then
				invalid_config(field, "expected a non-empty string or false")
			end
		end
	end

	if opts.dap ~= nil and type(opts.dap) ~= "boolean" then
		invalid_config("dap", "expected a boolean")
	end

	if opts.project_overrides ~= nil then
		validate_project_overrides(opts.project_overrides)
	end
end

local function merge(base, overrides)
	for key, value in pairs(overrides or {}) do
		if type(value) == "table" and type(base[key]) == "table" then
			merge(base[key], value)
		else
			base[key] = copy(value)
		end
	end
	return base
end

function Module.setup(opts)
	validate_options(opts)
	config = merge(copy(defaults), opts or {})
	return copy(config)
end

function Module.get()
	return copy(config or defaults)
end

return Module
