local M = {}

M.defaults = {
  -- How wrong characters are marked: "underline", "color", "background" or a list of them.
  -- "auto" picks a red underline when 'termguicolors' is set (colored underlines need it),
  -- otherwise red text for plain text files and a red background for code.
  indicator = "auto",
  error_color = "red",
  -- where the trainer buffer opens: "current", "split", "vsplit" or "tab"
  open = "current",
}

local INDICATORS = { auto = true, underline = true, color = true, background = true }
local PLAIN_FILETYPES = { text = true, markdown = true, rst = true, tex = true, plaintex = true }
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

  if not OPENS[cfg.open] then
    error(("typetrainer: invalid open '%s' (expected one of: %s)"):format(tostring(cfg.open), sorted_keys(OPENS)), 0)
  end
  if type(cfg.error_color) ~= "string" then
    error("typetrainer: error_color must be a string", 0)
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
  if vim.tbl_contains(indicators, "auto") and #indicators > 1 then
    error("typetrainer: indicator 'auto' cannot be combined with others", 0)
  end
  cfg.indicator = vim.deepcopy(indicators)
  return cfg
end

--- Whether a filetype is prose rather than code. Unknown filetypes count as plain.
---@param filetype string|nil
function M.is_plain(filetype)
  return filetype == nil or PLAIN_FILETYPES[filetype] == true
end

--- Turn "auto" into a concrete indicator list for this environment and target.
---@param indicators string[] normalized `indicator`
---@param ctx {termguicolors: boolean, plain: boolean}
---@return string[]
function M.resolve_indicator(indicators, ctx)
  if indicators[1] ~= "auto" then
    return indicators
  end
  if ctx.termguicolors then
    return { "underline" }
  end
  return { ctx.plain and "color" or "background" }
end

--- Highlight attributes (for nvim_set_hl) that implement the chosen indicators.
--- GUI colors need 'termguicolors' (and a colored underline needs terminal support),
--- so the cterm attributes always use plain red as a fallback.
---@param indicators string[] concrete indicators (no "auto")
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
    attrs.ctermfg = "Red"
  end
  if set.background then
    attrs.bg = color
    attrs.ctermbg = "Red"
    -- red text on a red background would be invisible
    if set.color then
      attrs.fg = "white"
      attrs.ctermfg = "White"
    end
  end
  return attrs
end

--- Parse the arguments of :TypeTrainer, e.g. `indicator=underline,color file.txt`.
---@param fargs string[]
---@return string|nil path, table|string opts_or_error
function M.parse_args(fargs)
  local opts, paths = {}, {}
  for _, arg in ipairs(fargs) do
    local key, value = arg:match("^(%a+)=(.+)$")
    if key == "open" then
      opts.open = value
    elseif key == "indicator" then
      opts.indicator = vim.split(value, ",", { plain = true })
    else
      paths[#paths + 1] = arg
    end
  end
  if #paths ~= 1 then
    return nil, "usage: :TypeTrainer [indicator=auto|underline,color,background]  [open=current|split|vsplit|tab] {file}"
  end
  return paths[1], opts
end

return M
