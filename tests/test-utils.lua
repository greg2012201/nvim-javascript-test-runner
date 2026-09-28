local Module = {}

function Module.absolute_path(path)
	local absolute = vim.fn.fnamemodify(path, ":p")
	if absolute == "/" then
		return absolute
	end
	return absolute:gsub("/+$", "")
end

return Module
