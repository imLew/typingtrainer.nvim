if vim.g.loaded_typetrainer then
  return
end
vim.g.loaded_typetrainer = 1

vim.api.nvim_create_user_command("TypeTrainer", function(args)
  local path, opts = require("typetrainer.config").parse_args(args.fargs)
  if not path then
    vim.notify(opts, vim.log.levels.ERROR)
    return
  end
  local session, err = require("typetrainer").start(path, opts)
  if not session then
    vim.notify("TypeTrainer: " .. err, vim.log.levels.ERROR)
  end
end, { nargs = "+", complete = "file", desc = "Practice typing a file shown as ghost text" })

vim.api.nvim_create_user_command("TypeTrainerStop", function()
  if not require("typetrainer").stop() then
    vim.notify("TypeTrainer: no active session in this buffer", vim.log.levels.WARN)
  end
end, { desc = "End the typing session in the current buffer" })
