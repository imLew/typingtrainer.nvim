local config = require("typetrainer.config")
local core = require("typetrainer.core")
local highlight = require("typetrainer.highlight")
local session = require("typetrainer.session")

local M = {}

local user_opts = {}

--- Configure defaults. Calling it is optional.
---@param opts? table see typetrainer.config.defaults
function M.setup(opts)
  local cfg = config.normalize(opts) -- validate before storing
  user_opts = opts or {}
  highlight.setup(cfg)
end

local OPEN_CMDS = { split = "split", vsplit = "vsplit", tab = "tab split" }

--- Open a new buffer showing `path` as ghost text.
---@param path string
---@param opts? table per-session overrides of the setup options
---@return table|nil session, string|nil err
function M.start(path, opts)
  local ok, cfg = pcall(config.normalize, vim.tbl_extend("force", user_opts, opts or {}))
  if not ok then
    return nil, cfg
  end
  local target, err = core.load(vim.fn.expand(path))
  if not target then
    return nil, err
  end
  highlight.setup(cfg, path)

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, ("typetrainer://%s#%d"):format(vim.fn.fnamemodify(path, ":t"), buf))
  if OPEN_CMDS[cfg.open] then
    vim.cmd(OPEN_CMDS[cfg.open])
  end
  vim.api.nvim_win_set_buf(0, buf)

  local s = session.new(buf, target, cfg)
  vim.cmd("startinsert")
  return s
end

--- Stop the session in `buf` (default: current buffer). The typed text stays.
function M.stop(buf)
  local s = session.get(buf)
  if s then
    s:stop()
  end
  return s ~= nil
end

--- Progress summary, handy for a statusline. Empty when no session is active.
function M.status(buf)
  local s = session.get(buf)
  if not s then
    return ""
  end
  local st = s:stats()
  return ("%d/%d chars, %d wrong"):format(st.correct, st.total, st.wrong)
end

--- The session attached to `buf` (default: current buffer).
M.session = session.get

return M
