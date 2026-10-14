local Module = {}
local Utils = require("javascript-test-runner.utils")

local read_json_file = Utils.read_json_file

local function join_path(directory, name)
	local normalized_directory = directory:gsub("[/\\]+$", "")
	if normalized_directory == "" then
		return "/" .. name
	end
	return normalized_directory .. "/" .. name
end

local function path_has_node_modules(path)
	for component in path:gsub("\\", "/"):gmatch("[^/]+") do
		if component == "node_modules" then
			return true
		end
	end
	return false
end

local function is_esm_file(path)
	if type(path) ~= "string" then
		return false
	end

	local filename = path:gsub("\\", "/"):match("([^/]+)$") or path
	return filename:match("%.mjs$") ~= nil or filename:match("%.mts$") ~= nil
end

local function is_under_test_directory(path)
	for component in path:gsub("\\", "/"):gmatch("[^/]+") do
		if component == "__tests__" then
			return true
		end
	end

	return false
end

local function is_conventional_esm_test(path)
	if type(path) ~= "string" then
		return false
	end

	local filename = path:gsub("\\", "/"):match("([^/]+)$") or path
	return is_under_test_directory(path)
		and is_esm_file(filename)
		or filename:match("%.test%.mjs$") ~= nil
		or filename:match("%.spec%.mjs$") ~= nil
		or filename:match("%.test%.mts$") ~= nil
		or filename:match("%.spec%.mts$") ~= nil
end

local function is_conventional_test(path)
	if type(path) ~= "string" then
		return false
	end

	local filename = path:gsub("\\", "/"):match("([^/]+)$") or path
	return (is_under_test_directory(path) and filename:match("%.[jt]sx?$") ~= nil)
		or filename:match("%.test%.[jt]sx?$") ~= nil
		or filename:match("%.spec%.[jt]sx?$") ~= nil
end

local function context_package_json(context)
	if type(context) ~= "table" then
		return nil
	end

	if type(context.package_json) == "string" and context.package_json ~= "" then
		return context.package_json
	end

	if type(context.root) == "string" and context.root ~= "" then
		return join_path(context.root, "package.json")
	end

	return nil
end

local function context_root(context)
	if type(context) ~= "table" then
		return nil
	end

	if type(context.root) == "string" and context.root ~= "" then
		return context.root
	end

	if type(context.package_json) == "string" and context.package_json ~= "" then
		return vim.fn.fnamemodify(context.package_json, ":h")
	end

	return nil
end

local function package_is_module(context)
	local package_json = context_package_json(context)
	if not package_json then
		return false
	end

	local contents = read_json_file(package_json)
	return type(contents) == "table" and contents.type == "module"
end

local function package_type_is_module(directory, inherited)
	local package_json = join_path(directory, "package.json")
	if vim.fn.filereadable(package_json) ~= 1 then
		return inherited
	end

	local contents = read_json_file(package_json)
	return type(contents) == "table" and contents.type == "module"
end

local function contains_esm_test_file(root, inherited_module_scope)
	if type(root) ~= "string" or root == "" then
		return false
	end

	root = vim.fn.fnamemodify(root, ":p")
	if path_has_node_modules(root) then
		return false
	end

	local function scan(directory, inherited_module_scope)
		local entries, scan_error = vim.fs.dir(directory)
		if type(entries) ~= "function" then
			error("Could not inspect ESM test scope " .. directory .. ": " .. tostring(scan_error))
		end

		local module_scope = package_type_is_module(directory, inherited_module_scope)
		for name, entry_type in entries do
			if name ~= "node_modules" then
				local path = join_path(directory, name)
				if entry_type == "directory" then
					if scan(path, module_scope) then
						return true
					end
				elseif entry_type == "file" then
					if is_conventional_esm_test(path) or (module_scope and is_conventional_test(path)) then
						return true
					end
				end
			end
		end

		return false
	end

	return scan(root, inherited_module_scope)
end

function Module.needs_vm_modules(options)
	if type(options) ~= "table" then
		return false
	end

	if package_is_module(options.context) then
		return true
	end

	if options.mode == "file" or options.mode == "line" then
		local file = options.file
		return type(file) == "string" and not path_has_node_modules(file) and is_esm_file(file)
	end

	if options.mode == "folder" then
		local folder = options.folder
		if type(folder) ~= "string" or folder == "" then
			if type(options.file) == "string" and options.file ~= "" then
				folder = vim.fn.fnamemodify(options.file, ":h")
			else
				folder = context_root(options.context)
			end
		end
		return contains_esm_test_file(folder, false)
	end

	if options.mode == "project" then
		return contains_esm_test_file(context_root(options.context), false)
	end

	return false
end

return Module
