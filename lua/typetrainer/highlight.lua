local config = require("typetrainer.config")

local M = {}

M.GHOST = "TypeTrainerGhost"
M.WRONG = "TypeTrainerWrong"

local current, current_path

local function apply()
  if not current then
    return
  end
  local filetype = current_path and vim.filetype.match({ filename = current_path }) or nil
  local indicators = config.resolve_indicator(current.indicator, {
    termguicolors = vim.o.termguicolors,
    plain = config.is_plain(filetype),
  })
  vim.api.nvim_set_hl(0, M.GHOST, { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, M.WRONG, config.highlight_attrs(indicators, current.error_color))
end

--- Define the highlight groups and keep them alive across :colorscheme.
---@param cfg table normalized config
---@param path? string target file, used by "auto" to tell prose from code
function M.setup(cfg, path)
  current, current_path = cfg, path
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("typetrainer_highlight", { clear = true }),
    callback = apply,
  })
end

return M
