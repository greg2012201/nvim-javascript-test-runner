local Module = {}
local Utils = require("javascript-test-runner.utils")

local read_json_file = Utils.read_json_file

local configuration_files = {
	jest = {
		"jest.config.js",
		"jest.config.cjs",
		"jest.config.mjs",
		"jest.config.ts",
		"jest.config.cts",
		"jest.config.mts",
		"jest.config.json",
	},
	vitest = {
		"vitest.config.js",
		"vitest.config.cjs",
		"vitest.config.mjs",
		"vitest.config.ts",
		"vitest.config.cts",
		"vitest.config.mts",
		"vitest.workspace.js",
		"vitest.workspace.ts",
	},
}

local function has_configuration(root, framework)
	for _, file in ipairs(configuration_files[framework]) do
		if vim.fn.filereadable(root .. "/" .. file) == 1 then
			return true
		end
	end
	return false
end

local function script_framework(scripts)
	if type(scripts) ~= "table" then
		return nil
	end

	local names = {}
	for name, script in pairs(scripts) do
		if type(name) == "string" and type(script) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names, function(left, right)
		if left == "test" then
			return right ~= "test"
		end
		if right == "test" then
			return false
		end
		return left < right
	end)

	for _, name in ipairs(names) do
		if name == "test" or name:match("^test[:%-]") then
			local script = scripts[name]
			local has_jest = script:match("%f[%w]jest%f[%W]") ~= nil
			local has_vitest = script:match("%f[%w]vitest%f[%W]") ~= nil
			if has_jest ~= has_vitest then
				return has_vitest and "vitest" or "jest"
			end
		end
	end

	return nil
end

local function dependency_framework(package_json)
	for _, field in ipairs({ "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" }) do
		local dependencies = package_json[field]
		if type(dependencies) == "table" then
			if dependencies.vitest ~= nil and dependencies.jest == nil then
				return "vitest"
			end
			if dependencies.jest ~= nil and dependencies.vitest == nil then
				return "jest"
			end
		end
	end

	return nil
end

function Module.detect(context)
	local root = context.root
	local package_json = read_json_file(context.package_json) or {}

	local from_script = script_framework(package_json.scripts)
	if from_script then
		return from_script
	end

	if has_configuration(root, "jest") then
		return "jest"
	end
	if has_configuration(root, "vitest") then
		return "vitest"
	end

	return dependency_framework(package_json) or "jest"
end

return Module
