local Module = {}

function Module.run_jest(mode)
	local utils = require("javascript-test-runner.utils")
	local invocation, err = utils.build_jest_invocation(mode)

	if not invocation then
		vim.notify(err or "Could not build test invocation.", vim.log.levels.ERROR)
		return false
	end

	vim.cmd("vsplit")

	local terminal_buffer = vim.api.nvim_get_current_buf()
	vim.bo[terminal_buffer].bufhidden = "wipe"
	vim.bo[terminal_buffer].buflisted = false

	local command = { invocation.command }
	for _, argument in ipairs(invocation.args) do
		table.insert(command, argument)
	end

	local job_id = vim.fn.jobstart(command, { cwd = invocation.cwd, term = true })
	if job_id <= 0 then
		vim.notify("Could not start Jest process.", vim.log.levels.ERROR)
		return false
	end

	vim.cmd("startinsert")

	return true
end

return Module
