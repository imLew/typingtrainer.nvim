-- End-to-end: drive a real child Neovim over RPC so the plugin runs under a genuine
-- event loop (startinsert, <Esc> mapping, TextChangedI, quit key).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local SNAPSHOT = [[
  local buf = ...
  local ns = require("typetrainer.session").ns
  local snap = { wrong = {}, ghost = {}, virt_lines = {} }
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.hl_group then
      snap.wrong[tostring(m[2])] = snap.wrong[tostring(m[2])] or {}
      table.insert(snap.wrong[tostring(m[2])], { m[3], d.end_col })
    elseif d.virt_text then
      snap.ghost[tostring(m[2])] = d.virt_text[1][1]
    elseif d.virt_lines then
      for _, l in ipairs(d.virt_lines) do table.insert(snap.virt_lines, l[1][1]) end
    end
  end
  return snap
]]

local function spawn()
  local chan = vim.fn.jobstart({
    vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE",
    "--cmd", "set rtp+=" .. root,
    "--cmd", "runtime plugin/typetrainer.lua",
  }, { rpc = true })
  assert(chan > 0, "could not start child nvim")
  local child = { chan = chan }
  function child.lua(code, ...)
    return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
  end
  function child.cmd(c)
    return vim.rpcrequest(chan, "nvim_command", c)
  end
  function child.send(keys)
    vim.rpcrequest(chan, "nvim_input", keys)
  end
  function child.lines()
    return child.lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  end
  function child.mode()
    return vim.rpcrequest(chan, "nvim_get_mode").mode
  end
  --- Poll until `fn()` returns a value equal to `expected`.
  function child.wait_for(fn, expected, what)
    local last
    local ok = vim.wait(3000, function()
      last = fn()
      return vim.deep_equal(last, expected)
    end, 20)
    if not ok then
      error(("timed out waiting for %s\nexpected: %s\n   actual: %s"):format(what, vim.inspect(expected), vim.inspect(last)), 2)
    end
  end
  function child.snapshot()
    return child.lua(SNAPSHOT, child.lua("return vim.api.nvim_get_current_buf()"))
  end
  function child.stop()
    pcall(vim.fn.jobstop, chan)
  end
  return child
end

--- Run `fn(child)` with a child that has a trainer session open on `lines`.
local function with_session(lines, opts, fn)
  local child = spawn()
  local path = tmpfile(lines)
  local ok, err = xpcall(function()
    local o = vim.tbl_extend("force", { mode = "insert" }, opts)
    child.lua("local s, err = require('typetrainer').start(...); assert(s, err)", path, o)
    fn(child)
  end, debug.traceback)
  child.stop()
  if not ok then
    error(err, 0)
  end
end

describe("e2e insert mode", function()
  it("starts in insert mode and renders ghost text", function()
    with_session({ "hello", "world" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      local snap = c.snapshot()
      eq("hello", snap.ghost["0"])
      eq({ "world" }, snap.virt_lines)
    end)
  end)

  it("accepts correct characters and flags wrong ones as you type", function()
    with_session({ "hello" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.send("hxl")
      c.wait_for(c.lines, { "hxl" }, "typed text")
      local snap = c.snapshot()
      eq({ ["0"] = { { 1, 2 } } }, snap.wrong)
      eq("lo", snap.ghost["0"])
    end)
  end)

  it("handles backspace and delete", function()
    with_session({ "hello" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.send("hxel<BS><BS><BS>")
      c.wait_for(c.lines, { "h" }, "backspaces")
      eq({}, c.snapshot().wrong)
      c.send("xello<Left><Left><Left><Left><Left><Del>")
      c.wait_for(c.lines, { "hello" }, "delete")
      eq({}, c.snapshot().wrong)
    end)
  end)

  it("does not leave insert mode on <Esc> or <C-c>", function()
    with_session({ "ab" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.send("a<Esc>b<C-c>")
      c.wait_for(c.lines, { "ab" }, "typed text")
      eq("i", c.mode())
    end)
  end)

  it("completes a multi-line text", function()
    with_session({ "ab", "", "cd" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.lua("vim.g.done = 0; vim.api.nvim_create_autocmd('User', { pattern = 'TypeTrainerComplete', callback = function() vim.g.done = vim.g.done + 1 end })")
      c.send("ab<CR><CR>cd")
      c.wait_for(function()
        return c.lua("return vim.g.done")
      end, 1, "completion event")
    end)
  end)

  it("ends with the quit key, leaving text in place", function()
    with_session({ "ab" }, {}, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.send("a<C-q>")
      c.wait_for(c.mode, "n", "normal mode")
      eq({ "a" }, c.lines())
      eq({}, c.snapshot().ghost)
      c.send("ix<Esc>")
      c.wait_for(c.lines, { "xa" }, "free editing after quit")
    end)
  end)

  it("honours a custom quit key", function()
    with_session({ "ab" }, { quit_key = "<C-x>" }, function(c)
      c.wait_for(c.mode, "i", "insert mode")
      c.send("<C-x>")
      c.wait_for(c.mode, "n", "normal mode")
    end)
  end)
end)

describe("e2e normal mode", function()
  it("lets <Esc> leave insert mode and use normal commands", function()
    with_session({ "hello world" }, { mode = "normal" }, function(c)
      c.wait_for(c.mode, "n", "normal mode")
      c.send("ihelxo world<Esc>")
      c.wait_for(c.lines, { "helxo world" }, "typed text")
      eq({ ["0"] = { { 3, 4 } } }, c.snapshot().wrong)
      c.send("0fxrl")
      c.wait_for(c.lines, { "hello world" }, "fixed text")
      eq({}, c.snapshot().wrong)
    end)
  end)

  it("highlights a mismatch made by a normal mode command", function()
    with_session({ "abc" }, { mode = "normal" }, function(c)
      c.send("iabc<Esc>")
      c.wait_for(c.lines, { "abc" }, "typed text")
      c.send("0rx")
      c.wait_for(c.lines, { "xbc" }, "replaced")
      eq({ ["0"] = { { 0, 1 } } }, c.snapshot().wrong)
    end)
  end)
end)

describe("e2e :TypeTrainer command", function()
  it("starts a session from the command line", function()
    local child = spawn()
    local path = tmpfile({ "hi" })
    local ok, err = xpcall(function()
      child.cmd("TypeTrainer mode=normal indicator=color " .. vim.fn.fnameescape(path))
      eq("hi", child.snapshot().ghost["0"])
      eq(true, child.lua("return vim.api.nvim_get_hl(0, { name = 'TypeTrainerWrong' }).fg ~= nil"))
      child.cmd("TypeTrainerStop")
      eq({}, child.snapshot().ghost)
    end, debug.traceback)
    child.stop()
    assert(ok, err)
  end)
end)
