local root = vim.fn.getcwd()
local mini_path = vim.env.MINI_NVIM_PATH or (root .. "/deps/mini.nvim")

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(mini_path)

if vim.fn.isdirectory(mini_path) == 0 then
  error("mini.nvim is required at " .. mini_path)
end

require("mini.test").setup()
