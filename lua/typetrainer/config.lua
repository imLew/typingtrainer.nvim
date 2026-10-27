local M = {}

M.defaults = {
  -- "insert": stay in insert mode (<Esc> is disabled, use `quit_key` or :TypeTrainerStop)
  -- "normal": edit freely with any normal mode command
  mode = "insert",
  -- how wrong characters are marked: "underline", "color", "background" or a list of them
  indicator = "underline",
  error_color = "#ff5555",
  -- insert mode only: key that ends the session
  quit_key = "<C-q>",
  -- where the trainer buffer opens: "current", "split", "vsplit" or "tab"
  open = "current",
}

local MODES = { insert = true, normal = true }
local INDICATORS = { underline = true, color = true, background = true }
local OPENS = { current = true, split = true, vsplit = true, tab = true }

local function sorted_keys(set)
  local keys = vim.tbl_keys(set)
  table.sort(keys)
  return table.concat(keys, ", ")
end

--- Merge user options over the defaults and validate them.
--- Raises an error for unknown keys or invalid values.
---@param opts? table
---@return table cfg with `indicator` always normalized to a list
function M.normalize(opts)
  local cfg = {}
  for k, v in pairs(M.defaults) do
    cfg[k] = v
  end
  for k, v in pairs(opts or {}) do
    if M.defaults[k] == nil then
      error(("typetrainer: unknown option '%s'"):format(k), 0)
    end
    cfg[k] = v
  end

  if not MODES[cfg.mode] then
    error(("typetrainer: invalid mode '%s' (expected one of: %s)"):format(tostring(cfg.mode), sorted_keys(MODES)), 0)
  end
  if not OPENS[cfg.open] then
    error(("typetrainer: invalid open '%s' (expected one of: %s)"):format(tostring(cfg.open), sorted_keys(OPENS)), 0)
  end
  if type(cfg.error_color) ~= "string" then
    error("typetrainer: error_color must be a string", 0)
  end
  if type(cfg.quit_key) ~= "string" then
    error("typetrainer: quit_key must be a string", 0)
  end

  local indicators = type(cfg.indicator) == "table" and cfg.indicator or { cfg.indicator }
  if #indicators == 0 then
    error("typetrainer: indicator must not be empty", 0)
  end
  for _, name in ipairs(indicators) do
    if not INDICATORS[name] then
      error(
        ("typetrainer: invalid indicator '%s' (expected one of: %s)"):format(tostring(name), sorted_keys(INDICATORS)),
        0
      )
    end
  end
  cfg.indicator = vim.deepcopy(indicators)
  return cfg
end

--- Highlight attributes (for nvim_set_hl) that implement the chosen indicators.
---@param indicators string[]
---@param color string
function M.highlight_attrs(indicators, color)
  local attrs = {}
  local set = {}
  for _, name in ipairs(indicators) do
    set[name] = true
  end
  if set.underline then
    attrs.underline = true
    attrs.sp = color
  end
  if set.color then
    attrs.fg = color
  end
  if set.background then
    attrs.bg = color
    -- red text on a red background would be invisible
    if set.color then
      attrs.fg = "white"
    end
  end
  return attrs
end

--- Parse the arguments of :TypeTrainer, e.g. `mode=normal indicator=underline,color file.txt`.
---@param fargs string[]
---@return string|nil path, table|string opts_or_error
function M.parse_args(fargs)
  local opts, paths = {}, {}
  for _, arg in ipairs(fargs) do
    local key, value = arg:match("^(%a+)=(.+)$")
    if key == "mode" or key == "open" then
      opts[key] = value
    elseif key == "indicator" then
      opts.indicator = vim.split(value, ",", { plain = true })
    else
      paths[#paths + 1] = arg
    end
  end
  if #paths ~= 1 then
    return nil, "usage: :TypeTrainer [mode=insert|normal] [indicator=underline,color,background] [open=...] {file}"
  end
  return paths[1], opts
end

return M
