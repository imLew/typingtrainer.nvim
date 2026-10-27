# typetrainer.nvim

A small typing trainer for Neovim. Open a file as **ghost text** in a new buffer and
reproduce it. Characters that diverge from the target are marked as you go.

Requires Neovim 0.9+.

## Usage

```vim
:TypeTrainer {file}                  " start; you begin in insert mode
:TypeTrainer indicator=underline,color {file}
:TypeTrainerStop                     " end the session, keep the text
```

Options may be given as `key=value` before the file: `indicator` (comma-separated list)
and `open`. Try `:TypeTrainer examples/hello.txt`.

Lua: `require("typetrainer").start(path, opts)`, `.stop(buf)`, `.status(buf)`
(`"12/340 chars, 2 wrong"`, for a statusline).

You start in insert mode, but nothing is locked: `<Esc>`, every normal mode command
(`dd`, `ciw`, `.`, `u`, ...) and every other mode work as usual. After each change the buffer
is compared with the target. A character that matches the ghost text is entered normally; one
that does not is entered too but marked as wrong. `<BS>` and `<Del>` work on both.

The ghost text is whatever remains of each target line after the characters you have typed
on it. Comparison is by position, so inserting a character early on a line marks the rest of
that line as wrong until you fix it. A line or character past the end of the target is wrong
too. When the buffer equals the target you get a notification with the number of characters,
keystrokes and seconds, and a `User TypeTrainerComplete` autocommand fires. Keystrokes are
every key you type in the trainer buffer, corrections included.

The trainer buffer turns off `autoindent`, `smartindent`, `expandtab`, `formatoptions`, etc.,
so what you type is exactly what is compared. Plugins that insert text for you (auto-pairs,
completion) should be disabled for this buffer.

## Configuration

Calling `setup` is optional. Defaults:

```lua
require("typetrainer").setup({
  indicator = "auto",   -- "auto" | "underline" | "color" | "background", or a list (not with "auto")
  error_color = "red",
  open = "current",     -- "current" | "split" | "vsplit" | "tab"
})
```

`"auto"` uses a red underline when `'termguicolors'` is set. Without it Neovim ignores the
underline color, so `auto` marks wrong characters with red text in plain text files
(text, markdown, unknown types) and a red background in code. Colored underlines also need a
terminal that supports them; if yours does not, use `indicator = { "underline", "color" }`
(the underline then takes the red of the text).

Ghost text uses the `TypeTrainerGhost` group (linked to `Comment`; override it freely).
Wrong characters use `TypeTrainerWrong`, derived from `indicator` and `error_color`.

## Limitations

- Ghost text is neovim virtual text and does not wrap; with very long lines use `nowrap`.
- The trainer compares by character position, not by edit distance.

## Tests

```sh
make test     # nvim --headless -u NONE -l tests/run.lua
```

No dependencies. `core_spec` and `config_spec` are unit tests of the pure logic,
`session_spec` covers buffer behaviour in-process, and `e2e_spec` drives a real child
Neovim over RPC (starting in insert mode, `TextChangedI` wiring, exact keystroke counts).
