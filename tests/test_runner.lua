local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local child = MiniTest.new_child_neovim()
local temporary_directories = {}
local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_case = function()
			for _, directory in ipairs(temporary_directories) do
				vim.fn.delete(directory, "rf")
			end
			temporary_directories = {}
		end,
		post_once = child.stop,
	},
})

local function capture_invocation(job_id)
	child.lua(string.format([[
		vim.fn.jobstart = function(command, options)
			_G.test_call_order = _G.test_call_order or {}
			_G.test_call_order[#_G.test_call_order + 1] = "jobstart"
			_G.test_job_exit = options.on_exit
			vim.g.test_invocation = {
				argv = command,
				cwd = options.cwd,
				env = options.env or {},
				env_is_dict = options.env == nil or not vim.islist(options.env),
				term = options.term,
				terminal_buffer = vim.api.nvim_get_current_buf(),
				terminal_window = vim.api.nvim_get_current_win(),
				job_id = %d,
			}
			return %d
		end
	]], job_id or 1, job_id or 1))
end

local function capture_mode_commands()
	child.lua([[
		local original_cmd = vim.cmd
		_G.test_mode_calls = {}
		_G.test_call_order = {}
		vim.cmd = function(command)
			if command == "startinsert" or command == "stopinsert" then
				_G.test_call_order[#_G.test_call_order + 1] = command
				_G.test_mode_calls[#_G.test_mode_calls + 1] = {
					command = command,
					buffer = vim.api.nvim_get_current_buf(),
					window = vim.api.nvim_get_current_win(),
				}
				return
			end
			return original_cmd(command)
		end
	]])
end

local function setup_runner_test_file()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd.edit("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")
		_G.test_source_window = vim.api.nvim_get_current_win()
		_G.test_source_buffer = vim.api.nvim_get_current_buf()
	]])
end

local function wait_for_mode_calls(count)
	child.lua(string.format([[vim.wait(100, function() return #_G.test_mode_calls >= %d end)]], count))
end

T["running tests"] = new_set()

T["running tests"]["runs a test file from its nearest project directory"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd.edit("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")
		_G.source_buffer = vim.api.nvim_get_current_buf()
	]])
	capture_invocation()
	child.cmd("Test file")

	eq(
		child.lua_get([[vim.g.test_invocation.cwd]]),
		absolute_path("tests/fixtures/project-discovery/monorepo/packages/widget")
	)
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
	eq(child.lua_get([[vim.g.test_invocation.terminal_buffer ~= _G.source_buffer]]), true)
	eq(child.lua_get([[vim.bo[vim.g.test_invocation.terminal_buffer].bufhidden]]), "hide")
	eq(child.lua_get([[vim.bo[vim.g.test_invocation.terminal_buffer].buflisted]]), true)

	child.lua([[vim.api.nvim_set_current_buf(_G.source_buffer)]])
	eq(child.lua_get([[vim.api.nvim_buf_is_valid(vim.g.test_invocation.terminal_buffer)]]), true)
end

T["running tests"]["starts terminal input in the runner window after successful startup"] = function()
	setup_runner_test_file()
	capture_invocation()
	capture_mode_commands()
	child.cmd("Test file")
	wait_for_mode_calls(1)

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart", "startinsert" })
	eq(child.lua_get([[_G.test_mode_calls]]), {
		{
			command = "startinsert",
			buffer = child.lua_get([[vim.g.test_invocation.terminal_buffer]]),
			window = child.lua_get([[vim.g.test_invocation.terminal_window]]),
		},
	})
	eq(child.lua_get([[vim.g.test_invocation.job_id]]), 1)
	eq(child.lua_get([[vim.api.nvim_buf_is_valid(vim.g.test_invocation.terminal_buffer)]]), true)
	eq(
		child.lua_get([[vim.api.nvim_win_get_buf(vim.g.test_invocation.terminal_window)]]),
		child.lua_get([[vim.g.test_invocation.terminal_buffer]])
	)
end

T["running tests"]["does not start terminal input when process startup fails"] = function()
	setup_runner_test_file()
	capture_invocation(0)
	capture_mode_commands()
	child.lua([[vim.notify = function() end]])
	child.lua([[pcall(vim.cmd, "Test file")]])
	wait_for_mode_calls(1)

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart" })
	eq(child.lua_get([[_G.test_mode_calls]]), {})
end

T["running tests"]["stops terminal input on exit only when its window is current and unchanged"] = function()
	setup_runner_test_file()
	capture_invocation()
	capture_mode_commands()
	child.cmd("Test file")
	wait_for_mode_calls(1)
	child.lua([[
		assert(type(_G.test_job_exit) == "function")
		_G.test_job_exit(1, 0, "exit")
		vim.wait(100, function() return #_G.test_mode_calls == 2 end)
	]])

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart", "startinsert", "stopinsert" })
	eq(child.lua_get([=[_G.test_mode_calls[2]]=]), {
		command = "stopinsert",
		buffer = child.lua_get([[vim.g.test_invocation.terminal_buffer]]),
		window = child.lua_get([[vim.g.test_invocation.terminal_window]]),
	})
end

T["running tests"]["does not steal source focus when the job exits"] = function()
	setup_runner_test_file()
	capture_invocation()
	capture_mode_commands()
	child.cmd("Test file")
	wait_for_mode_calls(1)
	child.lua([[
		vim.api.nvim_set_current_win(_G.test_source_window)
		_G.test_job_exit(1, 0, "exit")
		vim.wait(100, function() return #_G.test_mode_calls > 1 end)
	]])

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart", "startinsert" })
	eq(child.lua_get([[vim.api.nvim_get_current_win()]]), child.lua_get([[_G.test_source_window]]))
	eq(child.lua_get([[vim.api.nvim_get_current_buf()]]), child.lua_get([[_G.test_source_buffer]]))
	eq(child.lua_get([[vim.api.nvim_win_is_valid(vim.g.test_invocation.terminal_window)]]), true)
	eq(child.lua_get([[vim.api.nvim_buf_is_valid(vim.g.test_invocation.terminal_buffer)]]), true)
	eq(
		child.lua_get([[vim.api.nvim_win_get_buf(vim.g.test_invocation.terminal_window)]]),
		child.lua_get([[vim.g.test_invocation.terminal_buffer]])
	)
end

T["running tests"]["does not stop terminal input after its window changes buffers"] = function()
	setup_runner_test_file()
	capture_invocation()
	capture_mode_commands()
	child.cmd("Test file")
	wait_for_mode_calls(1)
	child.lua([[
		_G.test_other_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(vim.g.test_invocation.terminal_window, _G.test_other_buffer)
		_G.test_job_exit(1, 0, "exit")
		vim.wait(100, function() return #_G.test_mode_calls > 1 end)
	]])

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart", "startinsert" })
	eq(child.lua_get([[vim.api.nvim_get_current_win()]]), child.lua_get([[vim.g.test_invocation.terminal_window]]))
	eq(
		child.lua_get([[vim.api.nvim_win_get_buf(vim.g.test_invocation.terminal_window)]]),
		child.lua_get([[_G.test_other_buffer]])
	)
	eq(child.lua_get([[vim.api.nvim_buf_is_valid(vim.g.test_invocation.terminal_buffer)]]), true)
end

T["running tests"]["does not stop terminal input after its window closes"] = function()
	setup_runner_test_file()
	capture_invocation()
	capture_mode_commands()
	child.cmd("Test file")
	wait_for_mode_calls(1)
	child.lua([[
		vim.api.nvim_win_close(vim.g.test_invocation.terminal_window, true)
		_G.test_job_exit(1, 0, "exit")
		vim.wait(100)
	]])

	eq(child.lua_get([[_G.test_call_order]]), { "jobstart", "startinsert" })
	eq(child.lua_get([[vim.api.nvim_win_is_valid(vim.g.test_invocation.terminal_window)]]), false)
	eq(child.lua_get([[vim.api.nvim_get_current_win()]]), child.lua_get([[_G.test_source_window]]))
	eq(child.lua_get([[vim.api.nvim_get_current_buf()]]), child.lua_get([[_G.test_source_buffer]]))
end

T["running tests"]["uses the working directory for an unnamed project run"] = function()
	child.lua([[
		require("javascript-test-runner").setup()
		vim.cmd("cd tests/fixtures/project-discovery/independent/alpha/src")
		vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	]])
	capture_invocation()
	child.cmd("Test project")

	eq(
		child.lua_get([[vim.g.test_invocation.cwd]]),
		absolute_path("tests/fixtures/project-discovery/independent/alpha")
	)
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
end

T["running tests"]["runs a Vitest project through the public command"] = function()
	local project_root = absolute_path("tests/fixtures/pnpm-vitest")
	local nvm_dir = vim.fn.tempname()
	temporary_directories[#temporary_directories + 1] = nvm_dir
	local node = nvm_dir .. "/versions/node/v22/bin/node"
	local node_bin = nvm_dir .. "/versions/node/v22/bin"
	child.lua(string.format(
		[[
			local nvm_dir = %q
			vim.fn.mkdir(nvm_dir, "p")
			vim.fn.writefile({ "" }, nvm_dir .. "/nvm.sh")
			vim.env.NVM_DIR = nvm_dir
			vim.fn.executable = function(path)
				return path == %q and 1 or 0
			end
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						node_version = "22",
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		nvm_dir,
		node,
		project_root,
		project_root .. "/vitest.config.js"
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([[vim.g.test_invocation.argv]]), { "npm", "exec", "--", "vitest", "run" })
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), project_root)
	eq(
		child.lua_get(string.format([[vim.g.test_invocation.env.PATH:sub(1, #%q)]], node_bin)),
		node_bin
	)
	eq(
		child.lua_get(string.format([[vim.g.test_invocation.env.PATH:sub(#%q + 1, #%q + 1)]], node_bin, node_bin)),
		package.config:sub(3, 3)
	)
	eq(child.lua_get([[vim.g.test_invocation.env_is_dict]]), true)
	eq(child.lua_get([[vim.g.test_invocation.term]]), true)
end

T["running tests"]["uses nvm use for a project with .nvmrc and nvm installed"] = function()
	local project_root = absolute_path("tests/fixtures/node-resolution/nvmrc")
	local nvm_dir = vim.fn.tempname()
	temporary_directories[#temporary_directories + 1] = nvm_dir
	local node = nvm_dir .. "/versions/node/v20.11.1/bin/node"
	child.lua(string.format(
		[[
			local nvm_dir = %q
			local node = %q
			vim.fn.mkdir(vim.fn.fnamemodify(node, ":h"), "p")
			vim.fn.writefile({ "" }, node)
			vim.fn.writefile({ "" }, nvm_dir .. "/nvm.sh")
			vim.env.NVM_DIR = nvm_dir
			local executable = vim.fn.executable
			vim.fn.executable = function(path)
				return path == node and 1 or executable(path)
			end
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						package_manager = "npm",
						framework = "vitest",
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		nvm_dir,
		node,
		project_root,
		project_root .. "/package.json"
	))
	capture_invocation()
	child.cmd("Test project")

	local argv = child.lua_get([[vim.g.test_invocation.argv]])
	eq(argv[1], "bash")
	eq(argv[2], "--noprofile")
	eq(argv[3], "--norc")
	eq(argv[4], "-c")
	eq(argv[5]:find("nvm use", 1, true) ~= nil, true)
	eq(argv[6], "javascript-test-runner")
	eq(argv[7], nvm_dir)
	eq(argv[8], "npm")
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), project_root)
end

T["running tests"]["uses the resolved Node when .nvmrc exists but nvm is unavailable"] = function()
	local project_root = absolute_path("tests/fixtures/node-resolution/nvmrc")
	local nvm_dir = vim.fn.tempname()
	temporary_directories[#temporary_directories + 1] = nvm_dir
	child.lua(string.format(
		[[
			vim.fn.mkdir(%q, "p")
			vim.env.NVM_DIR = %q
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						package_manager = "npm",
						framework = "vitest",
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		nvm_dir,
		nvm_dir,
		project_root,
		project_root .. "/package.json"
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([=[vim.g.test_invocation.argv[1]]=]), "npm")
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), project_root)
end

T["running tests"]["does not invoke nvm use when .nvmrc is unavailable"] = function()
	local project_root = vim.fn.tempname()
	local nvm_dir = vim.fn.tempname()
	temporary_directories[#temporary_directories + 1] = project_root
	temporary_directories[#temporary_directories + 1] = nvm_dir
	child.lua(string.format(
		[[
			vim.fn.mkdir(%q, "p")
			vim.fn.writefile({ "{}" }, %q .. "/package.json")
			vim.fn.writefile({ "" }, %q .. "/vitest.config.js")
			vim.fn.mkdir(%q, "p")
			vim.fn.writefile({ "" }, %q .. "/nvm.sh")
			vim.env.NVM_DIR = %q
			require("javascript-test-runner").setup()
			vim.cmd.edit(%q .. "/vitest.config.js")
		]],
		project_root,
		project_root,
		project_root,
		nvm_dir,
		nvm_dir,
		nvm_dir,
		project_root
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([=[vim.g.test_invocation.argv[1]]=]), "npm")
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), project_root)
end

T["running tests"]["resolves overrides keyed by the workspace root"] = function()
	local workspace_root = absolute_path("tests/fixtures/project-discovery/monorepo")
	local file = absolute_path("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")
	local node = "/mock-nvm/versions/node/v22/bin/node"

	child.lua(string.format(
		[[
			vim.env.NVM_DIR = "/mock-nvm"
			vim.fn.executable = function(path)
				return path == %q and 1 or 0
			end
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						node_version = "22",
						package_manager = "pnpm",
						framework = "vitest",
					},
				},
			})
			vim.cmd.edit(%q)
			local project = require("javascript-test-runner.project")
			local context = project.detect(vim.api.nvim_buf_get_name(0))
			local environment = project.resolve_environment(context)
			vim.g.resolved_override_environment = {
				node_version = environment.node_version,
				node = environment.node,
				package_manager = environment.package_manager,
				framework = environment.framework,
			}
		]],
		node,
		workspace_root,
		file
	))

	eq(child.lua_get([[vim.g.resolved_override_environment]]), {
		node_version = "22",
		node = node,
		package_manager = "pnpm",
		framework = "vitest",
	})
end

T["running tests"]["uses the pnpm workspace marker when resolving project overrides"] = function()
	child.lua([[
		local workspace_root = vim.fn.tempname()
		local package_root = workspace_root .. "/packages/widget"
		vim.fn.mkdir(package_root .. "/src", "p")
		vim.fn.writefile({ "{}" }, workspace_root .. "/package.json")
		vim.fn.writefile({ "packages/*" }, workspace_root .. "/pnpm-workspace.yaml")
		vim.fn.writefile({ "{}" }, package_root .. "/package.json")
		local file = package_root .. "/src/feature.test.js"
		vim.fn.writefile({ "test('feature', () => {})" }, file)
		require("javascript-test-runner").setup({
			project_overrides = {
				[workspace_root] = {
					package_manager = "pnpm",
					framework = "vitest",
				},
			},
		})
		local project = require("javascript-test-runner.project")
		local context = project.detect(file)
		local environment = project.resolve_environment(context)
		vim.g.pnpm_workspace_root = workspace_root
		vim.g.pnpm_workspace_result = {
			root = context.root,
			package_manager = environment.package_manager,
			framework = environment.framework,
		}
		vim.fn.delete(workspace_root, "rf")
	]])

	eq(child.lua_get([[vim.g.pnpm_workspace_result]]), {
		root = child.lua_get([[vim.g.pnpm_workspace_root .. "/packages/widget"]]),
		package_manager = "pnpm",
		framework = "vitest",
	})
end

T["running tests"]["uses the nearest package root when no workspace marker exists"] = function()
	local root = absolute_path("tests/fixtures/pnpm-vitest")
	local file = absolute_path("tests/fixtures/pnpm-vitest/vitest.config.js")

	child.lua(string.format(
		[[
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						package_manager = "pnpm",
						framework = "jest",
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		root,
		file
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([[vim.g.test_invocation.argv]]), { "pnpm", "exec", "jest", "--runInBand" })
	eq(child.lua_get([[vim.g.test_invocation.cwd]]), root)
end

T["running tests"]["passes matching environment overrides only to the test process"] = function()
	local workspace_root = absolute_path("tests/fixtures/project-discovery/monorepo")
	local file = absolute_path("tests/fixtures/project-discovery/monorepo/packages/widget/src/nested/feature.test.js")

	child.lua(string.format(
		[[
			vim.env.JAVASCRIPT_TEST_RUNNER_OVERRIDE = "inherited"
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						env = {
							JAVASCRIPT_TEST_RUNNER_OVERRIDE = "configured",
							JAVASCRIPT_TEST_RUNNER_WORKSPACE = "enabled",
						},
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		workspace_root,
		file
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([[vim.g.test_invocation.env]]), {
		JAVASCRIPT_TEST_RUNNER_OVERRIDE = "configured",
		JAVASCRIPT_TEST_RUNNER_WORKSPACE = "enabled",
	})
	eq(child.lua_get([[vim.env.JAVASCRIPT_TEST_RUNNER_OVERRIDE]]), "inherited")
	eq(child.lua_get([[vim.env.JAVASCRIPT_TEST_RUNNER_WORKSPACE]]), vim.NIL)
end

T["running tests"]["does not apply workspace overrides to an unrelated project"] = function()
	local workspace_root = absolute_path("tests/fixtures/project-discovery/monorepo")
	local file = absolute_path("tests/fixtures/project-discovery/independent/alpha/src/example.test.js")

	child.lua(string.format(
		[[
			require("javascript-test-runner").setup({
				project_overrides = {
					[%q] = {
						package_manager = "pnpm",
						framework = "vitest",
						env = {
							JAVASCRIPT_TEST_RUNNER_WORKSPACE = "enabled",
						},
					},
				},
			})
			vim.cmd.edit(%q)
		]],
		workspace_root,
		file
	))
	capture_invocation()
	child.cmd("Test project")

	eq(child.lua_get([[vim.g.test_invocation.argv]]), { "npm", "exec", "--", "jest", "--runInBand" })
	eq(
		child.lua_get([[vim.g.test_invocation.cwd]]),
		absolute_path("tests/fixtures/project-discovery/independent/alpha")
	)
	eq(child.lua_get([[vim.g.test_invocation.env]]), {})
	eq(child.lua_get([[vim.env.JAVASCRIPT_TEST_RUNNER_WORKSPACE]]), vim.NIL)
end

return T
