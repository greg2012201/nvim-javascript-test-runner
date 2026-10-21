local Module = {}

function Module.normalize_path(path)
	local absolute_path = vim.fn.fnamemodify(path, ":p")
	if absolute_path ~= "/" then
		absolute_path = absolute_path:gsub("/+$", "")
	end
	return absolute_path
end

function Module.resolve_path(root, path)
	if path:sub(1, 1) == "/" then
		return Module.normalize_path(path)
	end
	return Module.normalize_path(root .. "/" .. path)
end

function Module.escape_test_name(name)
	local escaped_characters = {
		["\\"] = true,
		["^"] = true,
		["$"] = true,
		["("] = true,
		[")"] = true,
		["."] = true,
		["["] = true,
		["]"] = true,
		["*"] = true,
		["+"] = true,
		["?"] = true,
		["|"] = true,
		["{"] = true,
		["}"] = true,
	}
	local result = {}
	for index = 1, #name do
		local character = name:sub(index, index)
		if escaped_characters[character] then
			result[#result + 1] = "\\"
		end
		result[#result + 1] = character
	end
	return table.concat(result)
end

function Module.read_json_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

function Module.environment_with_node_path(environment)
	local env = {}
	for name, value in pairs(environment.env or {}) do
		env[name] = value
	end

	local node = environment.node
	if type(node) ~= "string" or node == "" or node == "node" then
		return env
	end

	local node_path = vim.fn.fnamemodify(node, ":p")
	local current_node = vim.fn.exepath("node")
	if env.PATH == nil and current_node == node_path then
		return env
	end

	local node_directory = vim.fn.fnamemodify(node, ":h")
	local path = env.PATH
	if path == nil then
		path = vim.env.PATH
	end

	if type(path) == "string" and path ~= "" then
		env.PATH = node_directory .. package.config:sub(3, 3) .. path
	else
		env.PATH = node_directory
	end

	return env
end

return Module
