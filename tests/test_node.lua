local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local fixture_root = absolute_path("tests/fixtures/node-resolution")

local function project_context(fixture_name)
  local root = absolute_path(fixture_root .. "/" .. fixture_name)
  return {
    root = root,
    package_json = root .. "/package.json",
  }
end

local function detect(context)
  return require("javascript-test-runner.node").detect(context)
end

local T = new_set()
T["Node.js resolution"] = new_set()

T["Node.js resolution"]["uses .nvmrc before other configured project versions"] = function()
  local environment = detect(project_context("nvmrc"))

  eq(environment.node_version, "20.11.1")
  eq(environment.source, ".nvmrc")
end

T["Node.js resolution"]["uses .node-version before package engines"] = function()
  local environment = detect(project_context("node-version"))

  eq(environment.node_version, "22.3.0")
  eq(environment.source, ".node-version")
end

T["Node.js resolution"]["uses package engines when no version file is present"] = function()
  local environment = detect(project_context("engines"))

  eq(environment.node_version, "18.19.1")
  eq(environment.source, "package.json")
end

T["Node.js resolution"]["falls back to the system Node executable"] = function()
  local system_node = vim.fn.exepath("node")
  if system_node == "" then
    system_node = "node"
  end

  local environment = detect(project_context("system"))

  eq(environment.node, system_node)
  eq(environment.node_version, nil)
  eq(environment.source, "system")
end

return T
