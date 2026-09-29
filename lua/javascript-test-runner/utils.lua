local Module = {}

function Module.read_json_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

return Module
