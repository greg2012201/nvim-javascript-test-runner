local Module = {}
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

function Module.resolve_environment(context)
	local node = require("javascript-test-runner.node").detect(context)
	local package_manager = require("javascript-test-runner.package-manager").detect(context)
	local framework = require("javascript-test-runner.framework").detect(context)

	return {
		node = node.node,
		node_version = node.node_version,
		package_manager = package_manager.name,
		framework = framework,
	}
end

return Module
