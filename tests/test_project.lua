local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local function absolute_path(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  if absolute == "/" then
    return absolute
  end
  return absolute:gsub("/+$", "")
end

local fixture_root = absolute_path("tests/fixtures/project-discovery")
local root_boundary_path = absolute_path("/")

local function fixture_path(relative_path)
  return absolute_path(fixture_root .. "/" .. relative_path)
end

local function detect(file_path)
  return require("javascript-test-runner.project").detect(file_path)
end

local T = new_set()
T["project discovery"] = new_set()

T["project discovery"]["uses the closest package boundary for a nested workspace file"] = function()
  local file_path = fixture_path("monorepo/packages/widget/src/nested/feature.test.js")
  local expected_root = fixture_path("monorepo/packages/widget")

  eq(detect(file_path), {
    root = expected_root,
    package_json = expected_root .. "/package.json",
  })
end

T["project discovery"]["returns no project for a path with no package ancestor"] = function()
  local file_path = vim.fn.fnamemodify(
    "/__javascript_test_runner_no_package__/src/nested/example.test.js",
    ":p"
  )

  eq(detect(file_path), nil)
end

T["project discovery"]["returns no project when given the filesystem root path"] = function()
  eq(detect(root_boundary_path), nil)
end

T["project discovery"]["resolves each file to its own project context"] = function()
  local alpha_file = fixture_path("independent/alpha/src/example.test.js")
  local beta_file = fixture_path("independent/beta/src/example.test.js")
  local projects = {
    detect(alpha_file),
    detect(beta_file),
  }

  eq(projects, {
    {
      root = fixture_path("independent/alpha"),
      package_json = fixture_path("independent/alpha/package.json"),
    },
    {
      root = fixture_path("independent/beta"),
      package_json = fixture_path("independent/beta/package.json"),
    },
  })
end

return T
