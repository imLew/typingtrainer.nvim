-- Pure text logic: comparing what the user typed with the target text.
-- Nothing here touches buffers, so it is cheap to unit test.
local M = {}

local function char_len(byte)
  if byte < 0xC0 then
    return 1
  elseif byte < 0xE0 then
    return 2
  elseif byte < 0xF0 then
    return 3
  end
  return 4
end

--- Split a string into UTF-8 characters.
---@param s string
---@return string[]
function M.chars(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local len = char_len(s:byte(i))
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

--- Number of UTF-8 characters in `s`.
function M.char_count(s)
  return #M.chars(s)
end

--- Strip carriage returns (CRLF files) and reject empty input.
---@param lines string[]
---@return string[]|nil, string|nil
function M.normalize_lines(lines)
  if not lines or #lines == 0 then
    return nil, "target is empty"
  end
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = (line:gsub("\r$", ""))
  end
  return out
end

--- Read a file as a list of target lines.
---@return string[]|nil, string|nil
function M.load(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, "cannot read file: " .. path
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "cannot read file: " .. path
  end
  local normalized, err = M.normalize_lines(lines)
  if not normalized then
    return nil, path .. ": " .. err
  end
  return normalized
end

--- Compare one typed line with its target line, character by character.
--- Characters typed beyond the end of the target are wrong too.
---@return integer[][] ranges 0-based byte ranges {start, end_exclusive}, adjacent ones merged
---@return integer wrong number of wrong characters
---@return integer typed number of typed characters
function M.diff_line(typed, target)
  local want = M.chars(target)
  local ranges, last = {}, nil
  local col, wrong, typed_count = 0, 0, 0
  for i, ch in ipairs(M.chars(typed)) do
    typed_count = typed_count + 1
    if ch ~= want[i] then
      wrong = wrong + 1
      if last and last[2] == col then
        last[2] = col + #ch
      else
        last = { col, col + #ch }
        ranges[#ranges + 1] = last
      end
    end
    col = col + #ch
  end
  return ranges, wrong, typed_count
end

--- The part of `target` not yet covered by `typed` (by character count).
function M.ghost(typed, target)
  local want = M.chars(target)
  return table.concat(want, "", M.char_count(typed) + 1)
end

--- Replace tabs with spaces so ghost text lines up with real tab stops.
---@param text string
---@param start_col integer display column where `text` starts
---@param tabstop integer
function M.expand_tabs(text, start_col, tabstop)
  if not text:find("\t", 1, true) then
    return text
  end
  local out, col = {}, start_col
  for _, ch in ipairs(M.chars(text)) do
    if ch == "\t" then
      local width = tabstop - (col % tabstop)
      out[#out + 1] = string.rep(" ", width)
      col = col + width
    else
      out[#out + 1] = ch
      col = col + vim.fn.strdisplaywidth(ch)
    end
  end
  return table.concat(out)
end

--- Compare every buffer line with the target.
---@param lines string[] buffer contents
---@param target string[]
---@param max_remaining? integer cap on how many untyped target lines to return
---@return table result {lines = {{wrong=, ghost=}...}, remaining = string[], typed = int, wrong = int}
function M.compare(lines, target, max_remaining)
  local result = { lines = {}, remaining = {}, typed = 0, wrong = 0 }
  for i, line in ipairs(lines) do
    local want = target[i] or ""
    local ranges, wrong, typed = M.diff_line(line, want)
    result.lines[i] = { wrong = ranges, ghost = M.ghost(line, want) }
    result.typed = result.typed + typed
    result.wrong = result.wrong + wrong
  end
  local last = math.min(#target, #lines + (max_remaining or #target))
  for i = #lines + 1, last do
    result.remaining[#result.remaining + 1] = target[i]
  end
  return result
end

--- The lines that should replace `lines[first..last]` after skipping or resetting them.
---   skip:  each line becomes its target line (ghost text turns real); lines past the
---          end of the target have nothing to skip to and are kept as they are
---   reset: each line is emptied so the whole target line shows as ghost text again;
---          lines past the end of the target are dropped, as there is no ghost to leave
---@param kind "skip"|"reset"
---@return string[]
function M.range_edit(lines, target, first, last, kind)
  local out = {}
  for i = first, last do
    local want = target[i]
    if kind == "skip" then
      out[#out + 1] = want or lines[i]
    elseif want then
      out[#out + 1] = ""
    end
  end
  return out
end

--- True when the buffer reproduces the target exactly.
function M.is_complete(lines, target)
  if #lines ~= #target then
    return false
  end
  for i, line in ipairs(lines) do
    if line ~= target[i] then
      return false
    end
  end
  return true
end

--- Total number of characters in the target (newlines not counted).
function M.total_chars(target)
  local n = 0
  for _, line in ipairs(target) do
    n = n + M.char_count(line)
  end
  return n
end

return M
