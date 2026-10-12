local Module = {}
local Utils = require("javascript-test-runner.utils")

local read_json_file = Utils.read_json_file

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function read_version_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	for _, line in ipairs(vim.fn.readfile(path)) do
		local version = trim(line):match("^([^%s#]+)")
		if version then
			return version
		end
	end

	return nil
end

local function read_tool_versions(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	for _, line in ipairs(vim.fn.readfile(path)) do
		local version = line:match("^%s*nodejs%s+([^%s#]+)") or line:match("^%s*node%s+([^%s#]+)")
		if version then
			return version
		end
	end

	return nil
end

local function read_mise_version(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local in_tools = false
	for _, line in ipairs(vim.fn.readfile(path)) do
		local section = line:match("^%s*%[([^%]]+)%]%s*$")
		if section then
			in_tools = section == "tools"
		elseif in_tools then
			local version = line:match("^%s*node%s*=%s*[\"']?([^\"'%s,%]]+)")
				or line:match("^%s*nodejs%s*=%s*[\"']?([^\"'%s,%]]+)")
			if version then
				return version
			end
		end
	end

	return nil
end

local function configured_version(context, package_json)
	local root = context.root
	local version = read_version_file(root .. "/.nvmrc")
	if version then
		return version, ".nvmrc", "nvm"
	end

	version = read_version_file(root .. "/.node-version")
	if version then
		return version, ".node-version", "fnm"
	end

	version = read_tool_versions(root .. "/.tool-versions")
	if version then
		return version, ".tool-versions", "asdf"
	end

	for _, file in ipairs({ ".mise.toml", "mise.toml", ".config/mise/config.toml" }) do
		version = read_mise_version(root .. "/" .. file)
		if version then
			return version, file, "mise"
		end
	end

	if type(package_json) == "table" then
		local volta = package_json.volta
		if type(volta) == "table" and type(volta.node) == "string" and volta.node ~= "" then
			return volta.node, "package.json", "volta"
		end

		local engines = package_json.engines
		if type(engines) == "table" and type(engines.node) == "string" and engines.node ~= "" then
			return engines.node, "package.json", nil
		end
	end

	return nil, nil, nil
end

local function system_node()
	local node = vim.fn.exepath("node")
	if node == "" then
		return "node"
	end
	return node
end

local function append_candidate(options)
	if options.base and options.base ~= "" then
		table.insert(options.candidates, options.base .. "/" .. options.relative_path)
	end
end

local function version_node_candidates(options)
	local version = options.version
	local manager = options.manager
	local version_override = options.version_override

	if not version:match("^[%w._+-]+$") then
		return {}
	end

	local version_directory = version:match("^v") and version or "v" .. version
	local plain_version = version:gsub("^v", "")
	local candidates = {}
	local home = vim.fn.expand("~")

	append_candidate({
		candidates = candidates,
		base = vim.env.NVM_DIR or (home .. "/.nvm"),
		relative_path = "versions/node/" .. version_directory .. "/bin/node",
	})
	append_candidate({
		candidates = candidates,
		base = vim.env.FNM_DIR or (vim.env.XDG_DATA_HOME or (home .. "/.local/share")) .. "/fnm",
		relative_path = "node-versions/" .. version_directory .. "/installation/bin/node",
	})
	append_candidate({
		candidates = candidates,
		base = vim.env.ASDF_DATA_DIR or (home .. "/.asdf"),
		relative_path = "installs/nodejs/" .. plain_version .. "/bin/node",
	})
	append_candidate({
		candidates = candidates,
		base = vim.env.MISE_DATA_DIR or (home .. "/.local/share/mise"),
		relative_path = "installs/node/" .. plain_version .. "/bin/node",
	})

	if manager == "volta" and not version_override then
		append_candidate({
			candidates = candidates,
			base = vim.env.VOLTA_HOME or (home .. "/.volta"),
			relative_path = "bin/node",
		})
	end

	return candidates
end

local function executable_node(path)
	if vim.fn.executable(path) == 1 then
		return path
	end
	return nil
end

local function can_run_manager(options)
	return vim.fn.executable(options.command) == 1 and type(vim.system) == "function"
end

local function run_manager(options)
	local command = options.command
	local args = options.args
	local root = options.root
	local env = options.env

	if not can_run_manager(options) then
		return nil
	end

	local argv = { command }
	vim.list_extend(argv, args)
	local result = vim.system(argv, { cwd = root, env, text = true }):wait()
	if result.code ~= 0 then
		return nil
	end

	return trim(result.stdout or "")
end

local function executable_from_result(path)
	if not path then
		return nil
	end

	if path:sub(1, 1) == "/" then
		return executable_node(path)
	end
	return nil
end

local function nvm_node(context, version)
	local nvm_dir = vim.env.NVM_DIR or (vim.fn.expand("~") .. "/.nvm")
	local nvm_script = nvm_dir .. "/nvm.sh"
	if type(vim.system) ~= "function" or vim.fn.filereadable(nvm_script) ~= 1 or vim.fn.executable("bash") ~= 1 then
		return nil
	end

	local result = vim.system({
		"bash",
		"--noprofile",
		"--norc",
		"-c",
		'source "$1" >/dev/null && nvm which "$2"',
		"nvm",
		nvm_script,
		version,
	}, { cwd = context.root, text = true }):wait()
	if result.code == 0 then
		return executable_from_result(trim(result.stdout or ""))
	end
	return nil
end

local function fnm_node(context, version)
	return executable_from_result(run_manager({
		command = "fnm",
		args = {
			"exec",
			"--using",
			version,
			"--",
			"node",
			"-p",
			"process.execPath",
		},
		root = context.root,
	}))
end

local function mise_node(context, version)
	return executable_from_result(run_manager({
		command = "mise",
		args = {
			"exec",
			"node@" .. version,
			"--",
			"node",
			"-p",
			"process.execPath",
		},
		root = context.root,
	}))
end

local function asdf_node(context, version)
	local install = run_manager({
		command = "asdf",
		args = { "where", "nodejs", version },
		root = context.root,
	})
	if install then
		return executable_node(install .. "/bin/node")
	end

	return executable_from_result(run_manager({
		command = "asdf",
		args = {
			"exec",
			"node",
			"-p",
			"process.execPath",
		},
		root = context.root,
		env = { ASDF_NODEJS_VERSION = version },
	}))
end

local function volta_node(context, version)
	return executable_from_result(run_manager({
		command = "volta",
		args = { "run", "--node", version, "--", "node", "-p", "process.execPath" },
		root = context.root,
	}))
end

local function manager_node(options)
	local context = options.context
	local version = options.version
	local manager = options.manager
	local version_override = options.version_override

	if manager == "nvm" then
		local node = nvm_node(context, version)
		if node or not version_override then
			return node
		end
	elseif manager == "fnm" then
		local node = fnm_node(context, version)
		if node or not version_override then
			return node
		end
	elseif manager == "mise" then
		local node = mise_node(context, version)
		if node or not version_override then
			return node
		end
	elseif manager == "asdf" then
		local node = asdf_node(context, version) or mise_node(context, version)
		if node or not version_override then
			return node
		end
	elseif manager == "volta" then
		if version_override then
			local node = volta_node(context, version)
			if node then
				return node
			end
		else
			return executable_from_result(run_manager({
				command = "volta",
				args = { "which", "node" },
				root = context.root,
			}))
		end
	end

	local node = nvm_node(context, version)
		or fnm_node(context, version)
		or mise_node(context, version)
		or asdf_node(context, version)

	if node then
		return node
	end

	if version_override then
		return volta_node(context, version)
	end

	return nil
end

local function managed_node(options)
	for _, path in ipairs(version_node_candidates({
		version = options.version,
		manager = options.manager,
		version_override = options.version_override,
	})) do
		local node = executable_node(path)
		if node then
			return node
		end
	end

	local node = manager_node(options)
	if node then
		return node
	end

	if options.version_override then
		return nil
	end

	return system_node()
end

function Module.detect(context, version_override)
	local package_json = read_json_file(context.package_json)
	local version, source, manager = configured_version(context, package_json)
	local has_version_override = type(version_override) == "string" and version_override ~= ""
	if has_version_override then
		version = version_override
		source = "project override"
	end

	if not version then
		return {
			node = system_node(),
			node_version = nil,
			source = "system",
		}
	end

	local node = managed_node({
		context = context,
		version = version,
		manager = manager,
		version_override = has_version_override,
	})
	if not node then
		return nil, "Could not resolve Node.js version override '" .. version .. "' to an executable."
	end

	return {
		node = node,
		node_version = version,
		source = source,
	}
end

return Module
