-- A session ties a target text to a buffer: it renders ghost text and
-- wrong-character marks, and reacts to edits.
local core = require("typetrainer.core")
local highlight = require("typetrainer.highlight")

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

M.ns = api.nvim_create_namespace("typetrainer")

local registry = {}

local Session = {}
Session.__index = Session

--- The session attached to `buf` (default: current buffer), if any.
function M.get(buf)
  return registry[buf or api.nvim_get_current_buf()]
end

--- Options that would otherwise alter what the user types.
local function lock_buffer_options(buf)
  local bo = vim.bo[buf]
  bo.autoindent = false
  bo.smartindent = false
  bo.cindent = false
  bo.indentexpr = ""
  bo.expandtab = false
  bo.softtabstop = 0
  bo.formatoptions = ""
  bo.textwidth = 0
  bo.wrapmargin = 0
  bo.comments = ""
end

---@param buf integer
---@param target string[]
---@param cfg table normalized config
function M.new(buf, target, cfg)
  local self = setmetatable({
    buf = buf,
    target = target,
    cfg = cfg,
    total = core.total_chars(target),
    keystrokes = 0,
    typed = 0,
    wrong = 0,
    completed = false,
    started_at = nil,
    group = api.nvim_create_augroup("typetrainer_" .. buf, { clear = true }),
  }, Session)
  registry[buf] = self

  lock_buffer_options(buf)

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = self.group,
    buffer = buf,
    callback = function()
      self:render()
    end,
  })
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = self.group,
    buffer = buf,
    callback = function()
      self:stop()
    end,
  })

  -- Every key typed while the trainer buffer is current counts as a keystroke.
  self.key_ns = api.nvim_create_namespace("typetrainer_keys_" .. buf)
  vim.on_key(function()
    if api.nvim_get_current_buf() == buf then
      self.keystrokes = self.keystrokes + 1
    end
  end, self.key_ns)

  self:render()
  return self
end

--- Redraw ghost text and wrong-character marks from the buffer's current contents.
function Session:render()
  local buf = self.buf
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_call(buf, function()
    api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local tabstop = vim.bo[buf].tabstop
    local result = core.compare(lines, self.target, vim.o.lines)

    for i, info in ipairs(result.lines) do
      local row = i - 1
      for _, range in ipairs(info.wrong) do
        api.nvim_buf_set_extmark(buf, M.ns, row, range[1], {
          end_col = range[2],
          hl_group = highlight.WRONG,
          priority = 200,
        })
      end
      if info.ghost ~= "" then
        local text = core.expand_tabs(info.ghost, vim.fn.strdisplaywidth(lines[i]), tabstop)
        api.nvim_buf_set_extmark(buf, M.ns, row, #lines[i], {
          virt_text = { { text, highlight.GHOST } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
        })
      end
    end

    if #result.remaining > 0 then
      local virt_lines = {}
      for _, text in ipairs(result.remaining) do
        virt_lines[#virt_lines + 1] = { { core.expand_tabs(text, 0, tabstop), highlight.GHOST } }
      end
      api.nvim_buf_set_extmark(buf, M.ns, #lines - 1, 0, { virt_lines = virt_lines })
    end

    self.typed, self.wrong = result.typed, result.wrong

    if not self.started_at and not (#lines == 1 and lines[1] == "") then
      self.started_at = uv.hrtime()
    end
    if core.is_complete(lines, self.target) then
      self:complete()
    else
      self.completed = false
    end
  end)
end

--- Skip (ghost text becomes real) or reset (typed text removed) the lines first..last.
--- Lines are 1-based and clamped to the buffer. One undo step.
---@param kind "skip"|"reset"
function Session:edit_lines(kind, first, last)
  local count = api.nvim_buf_line_count(self.buf)
  first, last = math.max(first, 1), math.min(last, count)
  if first > last then
    return
  end
  local lines = api.nvim_buf_get_lines(self.buf, 0, -1, false)
  local replacement = core.range_edit(lines, self.target, first, last, kind)
  api.nvim_buf_set_lines(self.buf, first - 1, last, false, replacement)

  -- skip: continue at the end of what was filled in; reset: start over at the line start
  local row, col
  if kind == "skip" then
    row = last
    col = #replacement[#replacement]
  else
    row = first
    col = 0
  end
  row = math.min(row, api.nvim_buf_line_count(self.buf))
  if api.nvim_get_current_buf() == self.buf then
    api.nvim_win_set_cursor(0, { row, col })
  end
  self:render()
end

function Session:skip(first, last)
  self:edit_lines("skip", first, last)
end

function Session:reset(first, last)
  self:edit_lines("reset", first, last)
end

function Session:complete()
  if self.completed then
    return
  end
  self.completed = true
  local seconds = self.started_at and (uv.hrtime() - self.started_at) / 1e9 or 0
  self.elapsed = seconds
  vim.notify(
    ("TypeTrainer: complete! %d characters, %d keystrokes, %.1fs"):format(self.total, self.keystrokes, seconds)
  )
  api.nvim_exec_autocmds("User", { pattern = "TypeTrainerComplete", modeline = false, data = { buf = self.buf } })
end

---@return table {typed, wrong, correct, total, keystrokes, complete}
function Session:stats()
  return {
    typed = self.typed,
    wrong = self.wrong,
    correct = self.typed - self.wrong,
    total = self.total,
    keystrokes = self.keystrokes,
    complete = self.completed,
  }
end

--- End the session: remove ghost text, marks, mappings and autocommands.
--- The buffer and its text stay.
function Session:stop()
  if registry[self.buf] ~= self then
    return
  end
  registry[self.buf] = nil
  vim.on_key(nil, self.key_ns)
  pcall(api.nvim_del_augroup_by_id, self.group)
  if api.nvim_buf_is_valid(self.buf) then
    api.nvim_buf_clear_namespace(self.buf, M.ns, 0, -1)
  end
end

return M
