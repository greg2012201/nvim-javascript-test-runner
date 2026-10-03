local Module = {}

local supported_backends = {
	jest = "javascript-test-runner.backends.jest",
	vitest = "javascript-test-runner.backends.vitest",
}

function Module.build_invocation(options)
	if type(options) ~= "table" then
		return nil, "Backend invocation options must be a table"
	end

	local environment = options.environment
	if type(environment) ~= "table" then
		return nil, "Backend invocation requires a resolved environment"
	end

	local backend_name = supported_backends[environment.framework]
	if not backend_name then
		return nil, "Unsupported test framework: " .. tostring(environment.framework)
	end

	return require(backend_name).build_invocation(options)
end

return Module
