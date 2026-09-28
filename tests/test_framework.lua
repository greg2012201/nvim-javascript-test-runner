local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local absolute_path = require("tests.test-utils").absolute_path

local fixture_root = absolute_path("tests/fixtures")

local project = require("javascript-test-runner.project")
local framework = require("javascript-test-runner.framework")

local function detect_framework(fixture)
	local package_json = fixture_root .. "/" .. fixture .. "/package.json"
	local context = project.detect(package_json)
	return framework.detect(context)
end

local T = new_set()
T["framework detection"] = new_set()

T["framework detection"]["detects Jest from its configuration file"] = function()
	eq(detect_framework("npm-jest"), "jest")
end

T["framework detection"]["detects Vitest from its configuration file"] = function()
	eq(detect_framework("pnpm-vitest"), "vitest")
end

T["framework detection"]["detects Jest from a package test script"] = function()
	eq(detect_framework("test-script"), "jest")
end

T["framework detection"]["detects Vitest from an installed dependency"] = function()
	eq(detect_framework("dependency-vitest"), "vitest")
end

T["framework detection"]["prefers configuration over conflicting dependency evidence"] = function()
	eq(detect_framework("config-over-dependency"), "jest")
end

T["framework detection"]["prefers package scripts in a project with both frameworks"] = function()
	eq(detect_framework("mixed-project"), "vitest")
end

return T
