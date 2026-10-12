local Module = {}
local Utils = require("javascript-test-runner.utils")
local Node = require("javascript-test-runner.node")
local PackageManager = require("javascript-test-runner.package-manager")
local Framework = require("javascript-test-runner.framework")
local Plugin = require("javascript-test-runner")

local read_json_file = Utils.read_json_file

local function normalize_path(path)
	local absolute_path = vim.fn.fnamemodify(path, ":p")
	if absolute_path ~= "/" then
		absolute_path = absolute_path:gsub("/+$", "")
	end
	return absolute_path
end

function Module.detect(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end

	local absolute_path = normalize_path(path)
	local current_dir = absolute_path
	if vim.fn.isdirectory(absolute_path) ~= 1 then
		current_dir = vim.fn.fnamemodify(absolute_path, ":h")
	end

	while true do
		local package_json = current_dir == "/" and "/package.json" or current_dir .. "/package.json"
		if vim.fn.filereadable(package_json) == 1 then
			local root = normalize_path(current_dir)
			return {
				root = root,
				package_json = root == "/" and "/package.json" or root .. "/package.json",
			}
		end

		local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
		if parent_dir == current_dir then
			return nil
		end
		current_dir = parent_dir
	end
end

local function is_workspace_root(root)
	local package_json = read_json_file(root .. "/package.json")
	if type(package_json) == "table" and package_json.workspaces ~= nil then
		return true
	end

	return vim.fn.filereadable(root .. "/pnpm-workspace.yaml") == 1
end

local function workspace_root(project_root)
	local current_dir = normalize_path(project_root)
	while true do
		if is_workspace_root(current_dir) then
			return current_dir
		end

		local parent_dir = normalize_path(vim.fn.fnamemodify(current_dir, ":h"))
		if parent_dir == current_dir then
			return normalize_path(project_root)
		end
		current_dir = parent_dir
	end
end

local function matching_override(root, overrides)
	if type(overrides) ~= "table" then
		return nil
	end

	for path, override in pairs(overrides) do
		if type(path) == "string" and path ~= "" and normalize_path(path) == root and type(override) == "table" then
			return override
		end
	end

	return nil
end

function Module.resolve_environment(context)
	local config = Plugin.get_config()
	local root = workspace_root(context.root)
	local override = matching_override(root, config.project_overrides)
	local node_version = override and override.node_version
	if type(node_version) ~= "string" or node_version == "" then
		node_version = nil
	end

	local node, node_error = Node.detect(context, node_version)
	if not node then
		return nil, node_error
	end

	local package_manager = PackageManager.detect(context)
	local framework = Framework.detect(context)

	if override and (override.package_manager == "npm" or override.package_manager == "pnpm") then
		package_manager = override.package_manager
	else
		package_manager = package_manager.name
	end

	if override and (override.framework == "jest" or override.framework == "vitest") then
		framework = override.framework
	end

	return {
		node = node.node,
		node_version = node.node_version,
		package_manager = package_manager,
		framework = framework,
		env = override and override.env or {},
	}
end

return Module
