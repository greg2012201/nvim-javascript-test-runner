local Module = {}
local Utils = require("javascript-test-runner.utils")

local read_json_file = Utils

local function is_file(path)
	return vim.fn.filereadable(path) == 1
end

local function project_root(project)
	if type(project) == "table" then
		return project.root
	end
	return project
end

function Module.detect(project)
	local root = project_root(project)
	local package_json = read_json_file(root .. "/package.json") or {}
	local declared = package_json.packageManager
	if type(declared) == "string" then
		local name = declared:match("^([%w_-]+)@")
		if name == "npm" or name == "pnpm" then
			return { name = name }
		end
	end

	if is_file(root .. "/pnpm-lock.yaml") then
		return { name = "pnpm" }
	end

	if is_file(root .. "/package-lock.json") then
		return { name = "npm" }
	end

	return { name = "npm" }
end

return Module
