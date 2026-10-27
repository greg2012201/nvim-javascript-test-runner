local Module = {}
local Config = require("javascript-test-runner.config")

local configured = false

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

function Module.setup(opts)
	if configured then
		return Module
	end

	local config = Config.setup(opts)
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

	if config.dap then
		require("javascript-test-runner.dap").setup()
	end

	configured = true
	return Module
end

return Module
