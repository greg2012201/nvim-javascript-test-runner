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

T["setup()"]["uses public defaults"] = function()
  setup()

  local config = child.lua_get([[
    (function()
      local runner = require("javascript-test-runner")
      local config = runner.get_config()
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
