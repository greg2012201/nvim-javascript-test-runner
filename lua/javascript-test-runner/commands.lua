local Module = {}

function Module.run(mode)
	return require("javascript-test-runner.runner").run(mode)
end

function Module.run_jest(mode)
	return Module.run(mode)
end

return Module
