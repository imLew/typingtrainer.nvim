# typetrainer.nvim

A small typing trainer for Neovim. Open a file as **ghost text** in a new buffer and
reproduce it. Characters that diverge from the target are marked as you go.

Requires Neovim 0.9+.

## Usage

```vim
:TypeTrainer {file}                  " start (insert mode by default)
:TypeTrainer mode=normal {file}      " free editing with all normal mode commands
:TypeTrainer indicator=underline,color {file}
:TypeTrainerStop                     " end the session, keep the text
```

Options may be given as `key=value` before the file: `mode`, `indicator`
(comma-separated list), `open`. Try `:TypeTrainer examples/hello.txt`.

Lua: `require("typetrainer").start(path, opts)`, `.stop(buf)`, `.status(buf)`
(`"12/340 chars, 2 wrong"`, for a statusline).

### Modes

- **insert** (default): you start in insert mode and stay there; `<Esc>` and `<C-c>` are
  disabled. Type the text. A character that matches the ghost text is entered normally; one that
  does not is entered too but marked as wrong. `<BS>` and `<Del>` work as usual on both.
  End the session with `<C-q>` (`quit_key`) or `:TypeTrainerStop` (via `<C-o>:`).
- **normal**: the same buffer, but `<Esc>` works and every normal mode command is available
  (`dd`, `ciw`, `.`, `u`, ...). Whatever the buffer holds is compared with the target after each change.

In both modes the ghost text is whatever remains of each target line after the characters
you have typed on it. Comparison is by position, so inserting a character early on a line
marks the rest of that line as wrong until you fix it. A line or character past the end of the
target is wrong too. When the buffer equals the target, you get a notification and a
`User TypeTrainerComplete` autocommand fires.

The trainer buffer turns off `autoindent`, `smartindent`, `expandtab`, `formatoptions`, etc.,
so what you type is exactly what is compared. Plugins that insert text for you (auto-pairs,
completion) should be disabled for this buffer.

## Configuration

Calling `setup` is optional. Defaults:

```lua
require("typetrainer").setup({
  mode = "insert",          -- "insert" | "normal"
  indicator = "underline",  -- "underline" | "color" | "background", or a list of them
  error_color = "#ff5555",
  quit_key = "<C-q>",       -- insert mode only
  open = "current",         -- "current" | "split" | "vsplit" | "tab"
})
```

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
Neovim over RPC (insert mode, `<Esc>` blocking, quit key, `TextChangedI` wiring).
