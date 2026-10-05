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

local configured = false
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

local function run(mode)
	return require("javascript-test-runner.commands").run(mode)
end

local function register_command(command_name)
	vim.api.nvim_create_user_command(command_name, function(command_opts)
		run(command_opts.args)
	end, {
		nargs = 1,
		complete = function()
			return { "file", "folder", "project", "line" }
		end,
	})
end

function Module.run(mode)
	return run(mode)
end

function Module.has_test_on_current_line()
	return require("javascript-test-runner.api").has_test_on_current_line()
end

function Module.get_config()
	return copy(config or defaults)
end

function Module.setup(opts)
	if configured then
		return Module
	end

	config = merge(copy(defaults), opts or {})
	register_command(config.command_name)

	if config.keymaps.file then
		vim.keymap.set("n", config.keymaps.file, function()
			run("file")
		end, { desc = "Test: Current File" })
	end

	if config.keymaps.line then
		vim.keymap.set("n", config.keymaps.line, function()
			run("line")
		end, { desc = "Test: Current Line" })
	end

	configured = true
	return Module
end

return Module
