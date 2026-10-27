local config = require("typetrainer.config")

local M = {}

M.GHOST = "TypeTrainerGhost"
M.WRONG = "TypeTrainerWrong"

local current

local function apply()
  if not current then
    return
  end
  vim.api.nvim_set_hl(0, M.GHOST, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, M.WRONG, config.highlight_attrs(current.indicator, current.error_color))
end

--- Define the highlight groups and keep them alive across :colorscheme.
---@param cfg table normalized config
function M.setup(cfg)
  current = cfg
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("typetrainer_highlight", { clear = true }),
    callback = apply,
  })
end

return M
