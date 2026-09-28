local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local fixture_root = absolute_path("tests/fixtures/package-manager")

local function fixture_path(relative_path)
  return absolute_path(fixture_root .. "/" .. relative_path)
end

local function detect_name(project)
  return require("javascript-test-runner.package-manager").detect(fixture_path(project)).name
end

local T = new_set()
T["package-manager detection"] = new_set()

T["package-manager detection"]["uses package.json packageManager before a conflicting pnpm lockfile"] = function()
  eq(detect_name("declared-npm-with-pnpm-lock"), "npm")
end

T["package-manager detection"]["detects pnpm from pnpm-lock.yaml"] = function()
  eq(detect_name("pnpm-lock"), "pnpm")
end

T["package-manager detection"]["prefers pnpm-lock.yaml to a conflicting package-lock.json"] = function()
  eq(detect_name("pnpm-and-npm-locks"), "pnpm")
end

T["package-manager detection"]["detects npm from package-lock.json"] = function()
  eq(detect_name("npm-lock"), "npm")
end

T["package-manager detection"]["falls back to npm when no manager declaration or lockfile exists"] = function()
  eq(detect_name("npm-fallback"), "npm")
end

return T
