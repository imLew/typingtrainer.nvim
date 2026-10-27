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

local function line_command(name, fn_name, desc)
  vim.api.nvim_create_user_command(name, function(args)
    if not require("typetrainer")[fn_name](args.line1, args.line2) then
      vim.notify("TypeTrainer: no active session in this buffer", vim.log.levels.WARN)
    end
  end, { range = true, desc = desc })
end

line_command("TypeTrainerSkip", "skip", "Fill in the ghost text of the lines in range (default: current line)")
line_command("TypeTrainerReset", "reset", "Remove typed text from the lines in range (default: current line)")

-- <Plug> mappings, to be bound by the user, e.g.
--   vim.keymap.set({ "n", "x" }, "gs", "<Plug>(TypeTrainerSkip)")   -- operator / visual
--   vim.keymap.set("n", "gss", "<Plug>(TypeTrainerSkipLine)")
-- Normal mode: an operator that takes any motion and acts on the lines it touches.
-- Visual mode (v, V and CTRL-V alike): acts on every selected line.
for _, def in ipairs({
  { name = "TypeTrainerSkip", command = "TypeTrainerSkip", op = "operator_skip" },
  { name = "TypeTrainerReset", command = "TypeTrainerReset", op = "operator_reset" },
}) do
  local function operator(suffix)
    return function()
      vim.o.operatorfunc = "v:lua.require'typetrainer'." .. def.op
      return "g@" .. suffix
    end
  end
  vim.keymap.set("n", ("<Plug>(%s)"):format(def.name), operator(""), { expr = true, desc = def.command .. " operator" })
  vim.keymap.set("n", ("<Plug>(%sLine)"):format(def.name), operator("_"), { expr = true, desc = def.command .. " line" })
  vim.keymap.set("x", ("<Plug>(%s)"):format(def.name), ":" .. def.command .. "<CR>", { silent = true, desc = def.command })
end
