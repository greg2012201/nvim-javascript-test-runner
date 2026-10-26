local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

local function setup()
  child.lua([[require("javascript-test-runner").setup()]])
end

T["setup()"] = new_set()

T["setup()"]["uses configured command and keymaps, including a disabled mapping"] = function()
  child.lua([[
    require("javascript-test-runner").setup({
      command_name = "JavaScriptTest",
      keymaps = {
        file = "<Leader>tx",
        line = false,
      },
    })
  ]])

  eq(child.lua_get([[
    (function()
      local config = require("javascript-test-runner.config").get()
      return {
        command_name = config.command_name,
        file_keymap = config.keymaps.file,
        line_keymap = config.keymaps.line,
      }
    end)()
  ]]), {
    command_name = "JavaScriptTest",
    file_keymap = "<Leader>tx",
    line_keymap = false,
  })
  eq(child.lua_get([[vim.fn.exists(":JavaScriptTest")]]), 2)
  eq(child.lua_get([[vim.fn.exists(":Test")]]), 0)
  eq(child.lua_get([[vim.fn.maparg("<Leader>tx", "n") ~= ""]]), true)
  eq(child.lua_get([[vim.fn.maparg("<Leader>tl", "n") ~= ""]]), false)
end

T["setup()"]["allows disabling the file mapping"] = function()
  child.lua([[
    require("javascript-test-runner").setup({
      keymaps = {
        file = false,
        line = "<Leader>ty",
      },
    })
  ]])

  eq(child.lua_get([[vim.fn.maparg("<Leader>tf", "n") ~= ""]]), false)
  eq(child.lua_get([[vim.fn.maparg("<Leader>ty", "n") ~= ""]]), true)
end

T["setup()"]["uses defaults through the config getter"] = function()
  setup()

  local config = child.lua_get([[
    (function()
      local config = require("javascript-test-runner.config").get()
      return {
        command_name = config.command_name,
        file_keymap = config.keymaps.file,
        line_keymap = config.keymaps.line,
        dap = config.dap,
      }
    end)()
  ]])

  eq(config, {
    command_name = "Test",
    file_keymap = "<Leader>tf",
    line_keymap = "<Leader>tl",
    dap = false,
  })
end

T["setup()"]["returns a defensive config copy"] = function()
  child.lua([[
    require("javascript-test-runner").setup({
      project_overrides = {
        ["/workspace/project"] = {
          env = {
            NODE_OPTIONS = "--existing",
          },
        },
      },
    })

    local config = require("javascript-test-runner.config").get()
    config.keymaps.file = "<Leader>changed"
    config.project_overrides["/workspace/project"].env.NODE_OPTIONS = "--changed"
  ]])

  eq(
    child.lua_get([[
      (function()
        local config = require("javascript-test-runner.config").get()
        return {
          file_keymap = config.keymaps.file,
          node_options = config.project_overrides["/workspace/project"].env.NODE_OPTIONS,
        }
      end)()
    ]]),
    {
      file_keymap = "<Leader>tf",
      node_options = "--existing",
    }
  )
end

T["setup()"]["rejects unsupported package-manager overrides"] = function()
  child.lua([[
    local ok, err = pcall(function()
      require("javascript-test-runner").setup({
        project_overrides = {
          ["/workspace/project"] = {
            package_manager = "yarn",
          },
        },
      })
    end)
    vim.g.invalid_override = { ok = ok, error = tostring(err) }
  ]])

  eq(child.lua_get([[vim.g.invalid_override.ok]]), false)
  eq(child.lua_get([[vim.g.invalid_override.error:find("package_manager", 1, true) ~= nil]]), true)
end

T["setup()"]["rejects unsupported framework overrides"] = function()
  child.lua([[
    local ok, err = pcall(function()
      require("javascript-test-runner").setup({
        project_overrides = {
          ["/workspace/project"] = {
            framework = "mocha",
          },
        },
      })
    end)
    vim.g.invalid_override = { ok = ok, error = tostring(err) }
  ]])

  eq(child.lua_get([[vim.g.invalid_override.ok]]), false)
  eq(child.lua_get([[vim.g.invalid_override.error:find("framework", 1, true) ~= nil]]), true)
end

T["setup()"]["accepts Node versions understood by version managers"] = function()
  child.lua([[
    require("javascript-test-runner").setup({
      project_overrides = {
        ["/workspace/project"] = {
          node_version = "lts/*",
        },
      },
    })
  ]])

  eq(
    child.lua_get([[
      require("javascript-test-runner.config").get().project_overrides["/workspace/project"].node_version
    ]]),
    "lts/*"
  )
end

T["setup()"]["rejects non-string project environment values"] = function()
  child.lua([[
    local ok, err = pcall(function()
      require("javascript-test-runner").setup({
        project_overrides = {
          ["/workspace/project"] = {
            env = {
              NODE_OPTIONS = false,
            },
          },
        },
      })
    end)
    vim.g.invalid_environment_override = { ok = ok, error = tostring(err) }
  ]])

  eq(child.lua_get([[vim.g.invalid_environment_override.ok]]), false)
  eq(child.lua_get([[vim.g.invalid_environment_override.error:find("env", 1, true) ~= nil]]), true)
end

T["setup()"]["does not load DAP by default"] = function()
  child.lua([[
    package.loaded["dap"] = nil
    package.preload["dap"] = function()
      error("nvim-dap should not be loaded")
    end
    require("javascript-test-runner").setup()
  ]])

  eq(child.lua_get([[package.loaded["dap"] == nil]]), true)
end

T["setup()"]["is idempotent"] = function()
  expect.no_error(function()
    child.lua([[
      local runner = require("javascript-test-runner")
      runner.setup()
      runner.setup()
    ]])
  end)

  eq(child.lua_get([[vim.fn.exists(":Test")]]), 2)
  eq(child.lua_get([[
    (function()
      local count = 0
      for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
        if mapping.lhs == "\\tf" or mapping.lhs == "\\tl" then
          count = count + 1
        end
      end
      return count
    end)()
  ]]), 2)
end

return T
