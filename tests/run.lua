-- Run with: nvim --headless -u NONE -l tests/run.lua [spec files...]
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. package.path
vim.cmd("runtime plugin/typetrainer.lua")

local files = #arg > 0 and arg or vim.fn.sort(vim.fn.glob(root .. "/tests/*_spec.lua", false, true))
local ok = require("tests.harness").run(files)
os.exit(ok and 0 or 1)
