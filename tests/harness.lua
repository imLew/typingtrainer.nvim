-- Tiny dependency-free test harness: describe / it / eq.
local M = {}

local suites, current = {}, nil

function _G.describe(name, fn)
  current = { name = name, tests = {} }
  suites[#suites + 1] = current
  fn()
  current = nil
end

function _G.it(name, fn)
  table.insert(current.tests, { name = name, fn = fn })
end

function _G.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      ("%sexpected: %s\n   actual: %s"):format(msg and (msg .. "\n") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

--- Type `keys` synchronously.
--- feedkeys() returns as soon as the typeahead is empty, before Neovim's input
--- loop would fire TextChanged(I), so fire the event a real keystroke would.
--- (tests/e2e_spec.lua checks that wiring against a real event loop.)
function _G.feed(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, "tx", false)
  local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  vim.api.nvim_exec_autocmds(insert and "TextChangedI" or "TextChanged", { buffer = 0 })
end

--- Fresh scratch file on disk with the given contents.
function _G.tmpfile(lines)
  local path = vim.fn.tempname()
  vim.fn.writefile(lines, path)
  return path
end

--- Marks (0-based byte ranges) and ghost virt_text of a buffer, by row.
function _G.snapshot(buf)
  local ns = require("typetrainer.session").ns
  local snap = { wrong = {}, ghost = {}, virt_lines = {} }
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local row, col, d = m[2], m[3], m[4]
    if d.hl_group then
      snap.wrong[row] = snap.wrong[row] or {}
      table.insert(snap.wrong[row], { col, d.end_col })
    elseif d.virt_text then
      snap.ghost[row] = d.virt_text[1][1]
    elseif d.virt_lines then
      for _, l in ipairs(d.virt_lines) do
        table.insert(snap.virt_lines, l[1][1])
      end
    end
  end
  return snap
end

--- Back to a clean editor between tests, whatever mode or mappings a test left behind.
local function reset_editor()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "tx", false)
  vim.cmd("silent! %bwipeout!")
  vim.cmd("silent! only")
end

function M.run(files)
  local passed, failed = 0, {}
  for _, file in ipairs(files) do
    suites = {}
    dofile(file)
    for _, suite in ipairs(suites) do
      for _, test in ipairs(suite.tests) do
        reset_editor()
        local ok, err = xpcall(test.fn, debug.traceback)
        local label = ("%s :: %s"):format(suite.name, test.name)
        if ok then
          passed = passed + 1
          print("  ok   " .. label)
        else
          failed[#failed + 1] = label
          print("  FAIL " .. label .. "\n" .. tostring(err) .. "\n")
        end
      end
    end
  end
  print(("\n%d passed, %d failed"):format(passed, #failed))
  return #failed == 0
end

return M
