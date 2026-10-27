-- In-process tests of session logic. Sessions use mode = "normal" and are driven
-- with explicit `i...<Esc>`: `startinsert` and the insert-only mappings need a real
-- event loop, which tests/e2e_spec.lua provides.
local typetrainer = require("typetrainer")
local session = require("typetrainer.session")

local function start(lines, opts)
  local s, err = typetrainer.start(tmpfile(lines), vim.tbl_extend("force", { mode = "normal" }, opts or {}))
  assert(s, err)
  return s
end

local function buf_lines(s)
  return vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
end

describe("start", function()
  it("opens a new buffer showing the target as ghost text", function()
    local s = start({ "hello", "world" })
    eq(s.buf, vim.api.nvim_get_current_buf())
    eq({ "" }, buf_lines(s))
    local snap = snapshot(s.buf)
    eq("hello", snap.ghost[0])
    eq({ "world" }, snap.virt_lines)
  end)

  it("starts in normal mode when mode = normal", function()
    start({ "ab" })
    eq("n", vim.api.nvim_get_mode().mode)
  end)

  it("returns an error for a missing file", function()
    local s, err = typetrainer.start("/nonexistent/x.txt")
    eq(nil, s)
    assert(err:find("cannot read file"), err)
  end)

  it("returns an error for invalid options", function()
    local s, err = typetrainer.start(tmpfile({ "a" }), { mode = "bogus" })
    eq(nil, s)
    assert(err:find("invalid mode"), err)
  end)

  it("disables options that would alter typed text", function()
    local s = start({ "x" })
    eq(false, vim.bo[s.buf].autoindent)
    eq(false, vim.bo[s.buf].expandtab)
    eq("", vim.bo[s.buf].formatoptions)
  end)

  it("opens in a split when asked", function()
    local before = #vim.api.nvim_tabpage_list_wins(0)
    start({ "x" }, { open = "split" })
    eq(before + 1, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("expands tabs in ghost text", function()
    local s = start({ "\tx", "\ty" })
    local pad = string.rep(" ", vim.bo[s.buf].tabstop)
    local snap = snapshot(s.buf)
    eq(pad .. "x", snap.ghost[0])
    eq({ pad .. "y" }, snap.virt_lines)
  end)
end)

describe("typing", function()
  it("accepts correct characters and shrinks the ghost text", function()
    local s = start({ "hello" })
    feed("ihel<Esc>")
    eq({ "hel" }, buf_lines(s))
    local snap = snapshot(s.buf)
    eq("lo", snap.ghost[0])
    eq({}, snap.wrong)
  end)

  it("keeps wrong characters and marks them", function()
    local s = start({ "hello" })
    feed("ihxl<Esc>")
    eq({ "hxl" }, buf_lines(s))
    eq({ [0] = { { 1, 2 } } }, snapshot(s.buf).wrong)
    eq(1, s:stats().wrong)
    eq(2, s:stats().correct)
  end)

  it("lets backspace remove wrong and correct characters", function()
    local s = start({ "hello" })
    feed("ihx<BS><Esc>")
    eq({ "h" }, buf_lines(s))
    eq({}, snapshot(s.buf).wrong)
    feed("a<BS><Esc>")
    eq({ "" }, buf_lines(s))
    eq("hello", snapshot(s.buf).ghost[0])
  end)

  it("lets delete remove the character under the cursor", function()
    local s = start({ "hello" })
    feed("ihxello<Left><Left><Left><Left><Left><Del><Esc>")
    eq({ "hello" }, buf_lines(s))
    eq({}, snapshot(s.buf).wrong)
    eq(true, s:stats().complete)
  end)

  it("advances ghost text line by line on <CR>", function()
    local s = start({ "ab", "cd", "ef" })
    feed("iab<CR>c<Esc>")
    eq({ "ab", "c" }, buf_lines(s))
    local snap = snapshot(s.buf)
    eq("d", snap.ghost[1])
    eq({ "ef" }, snap.virt_lines)
  end)

  it("does not auto-indent after <CR>", function()
    local s = start({ "  ab", "cd" })
    feed("i  ab<CR><Esc>")
    eq({ "  ab", "" }, buf_lines(s))
    eq("cd", snapshot(s.buf).ghost[1])
  end)

  it("types literal tabs", function()
    local s = start({ "\tx" })
    feed("i<Tab>x<Esc>")
    eq({ "\tx" }, buf_lines(s))
    eq({}, snapshot(s.buf).wrong)
  end)

  it("marks characters past the end of a line", function()
    local s = start({ "ab", "cd" })
    feed("iabc<Esc>")
    eq({ [0] = { { 2, 3 } } }, snapshot(s.buf).wrong)
  end)

  it("marks extra lines", function()
    local s = start({ "ab" })
    feed("iab<CR>zz<Esc>")
    eq({ [1] = { { 0, 2 } } }, snapshot(s.buf).wrong)
  end)

  it("handles multibyte characters", function()
    local s = start({ "café ok" })
    feed("icafé<Esc>")
    eq({}, snapshot(s.buf).wrong)
    eq(" ok", snapshot(s.buf).ghost[0])
    feed("ax<Esc>")
    eq({ [0] = { { 5, 6 } } }, snapshot(s.buf).wrong)
  end)
end)

describe("completion", function()
  it("fires once when the text is reproduced, and reports progress", function()
    local fired = 0
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "TypeTrainerComplete",
      callback = function()
        fired = fired + 1
      end,
    })
    local notified = {}
    local orig = vim.notify
    vim.notify = function(msg)
      table.insert(notified, msg)
    end

    local s = start({ "ab", "c" })
    feed("iab<CR><Esc>")
    eq(0, fired)
    feed("ic<Esc>")
    eq(1, fired)
    eq(true, s:stats().complete)
    assert(notified[1]:find("complete"), vim.inspect(notified))
    eq("3/3 chars, 0 wrong", typetrainer.status(s.buf))

    -- breaking it and fixing it again completes again
    feed("ax<Esc>")
    eq(false, s:stats().complete)
    feed("x")
    eq(2, fired)

    vim.notify = orig
    vim.api.nvim_del_autocmd(id)
  end)

  it("is not complete with an error in the text", function()
    local s = start({ "ab" })
    feed("iax<Esc>")
    eq(false, s:stats().complete)
  end)
end)

describe("normal mode editing", function()
  it("highlights divergence after edits and clears it on undo", function()
    local s = start({ "hello world" })
    feed("ihello world<Esc>")
    eq({}, snapshot(s.buf).wrong)
    feed("0xx")
    -- "llo world" now sits at the wrong offset, so the whole line diverges
    eq({ { 0, 9 } }, snapshot(s.buf).wrong[0])
    feed("uu")
    eq({ "hello world" }, buf_lines(s))
    eq({}, snapshot(s.buf).wrong)
  end)

  it("lets motions and operators fix mistakes", function()
    local s = start({ "hello world" })
    feed("ihelxo world<Esc>")
    eq({ [0] = { { 3, 4 } } }, snapshot(s.buf).wrong)
    feed("0fxrl")
    eq({ "hello world" }, buf_lines(s))
    eq({}, snapshot(s.buf).wrong)
    eq(true, s:stats().complete)
  end)

  it("supports o, dd and p", function()
    local s = start({ "a", "b" })
    feed("iaa<Esc>")
    eq({ [0] = { { 1, 2 } } }, snapshot(s.buf).wrong)
    feed("x") -- fix it; cursor sits on the second 'a'
    feed("ob<Esc>")
    eq({ "a", "b" }, buf_lines(s))
    eq(true, s:stats().complete)
    feed("ggddp")
    eq({ "b", "a" }, buf_lines(s))
    eq({ [0] = { { 0, 1 } }, [1] = { { 0, 1 } } }, snapshot(s.buf).wrong)
  end)
end)

describe("stop", function()
  it("removes ghost text but keeps the buffer", function()
    local s = start({ "ab" })
    eq(true, typetrainer.stop())
    eq({}, vim.api.nvim_buf_get_extmarks(s.buf, session.ns, 0, -1, {}))
    eq(false, typetrainer.stop())
    eq("", typetrainer.status())
  end)

  it("stops reacting to edits", function()
    local s = start({ "ab" })
    typetrainer.stop()
    feed("ixx<Esc>")
    eq({}, vim.api.nvim_buf_get_extmarks(s.buf, session.ns, 0, -1, {}))
  end)

  it("cleans up when the buffer is wiped", function()
    local s = start({ "ab" })
    local buf = s.buf
    vim.cmd("enew")
    vim.cmd("bwipeout! " .. buf)
    eq(nil, session.get(buf))
  end)
end)

describe("commands and setup", function()
  it(":TypeTrainer starts a session and :TypeTrainerStop ends it", function()
    vim.cmd("TypeTrainer mode=normal " .. vim.fn.fnameescape(tmpfile({ "hi" })))
    assert(session.get(), "no session")
    vim.cmd("TypeTrainerStop")
    eq(nil, session.get())
  end)

  it(":TypeTrainer reports errors via notify", function()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      table.insert(msgs, { msg, level })
    end
    vim.cmd("TypeTrainer /nonexistent/x.txt")
    vim.cmd("TypeTrainer mode=normal") -- no file given
    eq(false, pcall(vim.cmd, "TypeTrainer")) -- nargs=+ rejects this itself
    vim.notify = orig
    eq(2, #msgs)
    assert(msgs[1][1]:find("cannot read file"), vim.inspect(msgs))
    eq(vim.log.levels.ERROR, msgs[1][2])
    assert(msgs[2][1]:find("usage"), vim.inspect(msgs))
  end)

  it(":TypeTrainerStop warns without a session", function()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      table.insert(msgs, { msg, level })
    end
    vim.cmd("TypeTrainerStop")
    vim.notify = orig
    eq(vim.log.levels.WARN, msgs[1][2])
  end)

  it("setup applies the indicator to the highlight group", function()
    typetrainer.setup({ indicator = { "color" }, error_color = "#123456" })
    eq(0x123456, vim.api.nvim_get_hl(0, { name = "TypeTrainerWrong" }).fg)
    typetrainer.setup({})
    eq(true, vim.api.nvim_get_hl(0, { name = "TypeTrainerWrong" }).underline)
  end)

  it("setup defaults are used by start and overridden per call", function()
    typetrainer.setup({ mode = "normal", open = "split" })
    local before = #vim.api.nvim_tabpage_list_wins(0)
    local s = assert(typetrainer.start(tmpfile({ "a" })))
    eq(before + 1, #vim.api.nvim_tabpage_list_wins(0))
    eq("normal", s.cfg.mode)
    s = assert(typetrainer.start(tmpfile({ "a" }), { open = "current" }))
    eq(before + 1, #vim.api.nvim_tabpage_list_wins(0))
    typetrainer.setup({})
  end)

  it("setup rejects invalid options and keeps the old config", function()
    eq(false, (pcall(typetrainer.setup, { indicator = "nope" })))
    local s = assert(typetrainer.start(tmpfile({ "a" }), { mode = "normal" }))
    eq({ "underline" }, s.cfg.indicator)
  end)
end)
