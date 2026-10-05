local Module = {}
local Project = require("javascript-test-runner.project")
local Utils = require("javascript-test-runner.utils")

local escape_test_name = Utils.escape_test_name

local modes = {
	file = true,
	folder = true,
	project = true,
	line = true,
}

local function get_current_folder_path()
	local path = vim.fn.expand("%:p:h")
	if path == "" then
		return vim.fn.getcwd()
	end
	return path
end

local function get_project_context()
	local path = vim.fn.expand("%:p")
	if path == "" then
		path = vim.fn.getcwd()
	end
	return Project.detect(path)
end

local function get_current_test_file()
	local path = vim.fn.expand("%:p")
	if path == "" then
		return nil
	end
	return path
end

local function get_current_test_folder()
	return get_current_folder_path()
end

local function get_current_test_name_in_line(line)
	local single_quoted_name = line:match("^%s*[%w_%.]+%s*%(%s*'([^']*)'")
	if single_quoted_name then
		return single_quoted_name
	end

	return line:match('^%s*[%w_%.]+%s*%(%s*"([^"]*)"')
end

local function get_current_line()
	return vim.api.nvim_get_current_line()
end

local function get_node_command()
	local nvm_bin = vim.env.NVM_BIN
	if nvm_bin and #nvm_bin > 0 then
		local nvm_node = nvm_bin .. "/node"
		if vim.fn.executable(nvm_node) == 1 then
			return nvm_node
		end
	end
	return "node"
end

local function resolve_jest(project_root)
	local jest_script = project_root .. "/node_modules/jest/bin/jest.js"
	if vim.fn.filereadable(jest_script) == 1 then
		return {
			command = get_node_command(),
			args = { jest_script },
			cwd = project_root,
		}
	end

	local jest_binary = project_root .. "/node_modules/.bin/jest"
	if vim.fn.filereadable(jest_binary) == 1 or vim.fn.executable(jest_binary) == 1 then
		return {
			command = jest_binary,
			args = {},
			cwd = project_root,
		}
	end

	return {
		command = "npx",
		args = { "jest" },
		cwd = project_root,
	}
end

function Module.has_test_on_current_line()
	return Module.get_current_test_name_in_line(get_current_line()) ~= nil
end

function Module.get_current_test_name_in_line(line)
	return get_current_test_name_in_line(line)
end

function Module.build_jest_invocation(mode)
	if not modes[mode] then
		return nil, "Invalid Jest mode. Use file, folder, project, or line."
	end

	local project_context = get_project_context()
	if not project_context then
		return nil, "Could not find a project root containing package.json."
	end

	local invocation = resolve_jest(project_context.root)
	table.insert(invocation.args, "--runInBand")

	if mode == "file" then
		local test_file = get_current_test_file()
		if not test_file then
			return nil, "The current buffer does not contain a test file."
		end
		table.insert(invocation.args, "--runTestsByPath")
		table.insert(invocation.args, test_file)
	elseif mode == "folder" then
		table.insert(invocation.args, get_current_test_folder())
	elseif mode == "line" then
		local test_file = get_current_test_file()
		local test_name = get_current_test_name_in_line(get_current_line())
		if not test_file then
			return nil, "The current buffer does not contain a test file."
		end
		if not test_name then
			return nil, "No Jest test was found on the current line."
		end
		table.insert(invocation.args, "--runTestsByPath")
		table.insert(invocation.args, test_file)
		table.insert(invocation.args, "-t")
		local escaped_test_name = escape_test_name(test_name)
		table.insert(invocation.args, escaped_test_name)
	end

	return invocation
end

return Module
