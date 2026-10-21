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

local vm_modules_option = "--experimental-vm-modules"

local function is_vm_modules_option(option)
	return option == vm_modules_option
		or option == "'" .. vm_modules_option .. "'"
		or option == '"' .. vm_modules_option .. '"'
end

local function remove_vm_modules_options(options)
	local parts = {}
	local position = 1

	while position <= #options do
		local first, last = options:find("%S+", position)
		if not first then
			parts[#parts + 1] = options:sub(position)
			break
		end

		parts[#parts + 1] = options:sub(position, first - 1)
		local option = options:sub(first, last)
		if not is_vm_modules_option(option) then
			parts[#parts + 1] = option
		end
		position = last + 1
	end

	return table.concat(parts)
end

local function merge_node_options(configured, inherited)
	if type(configured) ~= "string" then
		configured = ""
	end
	if type(inherited) ~= "string" then
		inherited = ""
	end
	if configured == "" then
		return inherited
	end
	if inherited == "" then
		return configured
	end
	return configured .. " " .. inherited
end

local function resolve_env(params)
	local context = params.context
	local framework = params.framework
	local configured_env = params.configured_env
	local scope = params.scope

	local env = {}
	for name, value in pairs(configured_env or {}) do
		env[name] = value
	end

	if framework ~= "jest" then
		return env
	end

	local needs_vm_modules = require("javascript-test-runner.esm").needs_vm_modules({
		context = context,
		mode = scope.mode,
		file = scope.file,
		folder = scope.folder,
	})

	if not needs_vm_modules then
		return env
	end

	local node_options = merge_node_options(env.NODE_OPTIONS, vim.env.NODE_OPTIONS)
	node_options = remove_vm_modules_options(node_options)
	if node_options:match("%S") and not node_options:match("%s$") then
		node_options = node_options .. " "
	end
	env.NODE_OPTIONS = node_options .. vm_modules_option

	return env
end

function Module.resolve_environment(context, scope)
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

	scope = scope or {}
	return {
		node = node.node,
		node_version = node.node_version,
		node_source = node.source,
		package_manager = package_manager,
		framework = framework,
		env = resolve_env({
			context = context,
			framework = framework,
			configured_env = override and override.env,
			scope = {
				mode = scope.mode or "project",
				file = scope.file,
				folder = scope.folder,
			},
		}),
	}
end

return Module
