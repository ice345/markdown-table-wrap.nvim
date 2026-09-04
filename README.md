# markdown-table-wrap.nvim

A Neovim/LazyVim plugin for rendering Markdown pipe tables with wrapped cell
content.

The default experience is a stable, full-document Reader: when a supported
Markdown buffer contains a table, the plugin opens a protected rendered view
automatically. The original Markdown Source remains canonical and automatic
rendering never rewrites it. Explicit cell and structural editing commands are
the only operations that intentionally change Source.

## Preview

Inline rendering in a Tokyo Night themed Markdown buffer:

![Inline table rendering](docs/01-inline-tokyonight.png)

Viewport scrolling for rendered tables taller than their source table:

<div align="center">
  <video src="https://github.com/user-attachments/assets/5bb6da3d-04f0-4608-8672-f6edfb10f2c4" width="100%"></video>
</div>

Full inline expansion and a floating preview:

**Full inline rendering:**

![Full inline rendering](docs/02b-inline-full-toggle.png)


**Floating long table preview:**

![Floating long table preview](docs/03-floating-long-table.png)


## Why

Normal Neovim line wrapping breaks an entire Markdown source row, so table
borders no longer line up when one cell contains long prose, CJK text, code, or
a URL. `markdown-table-wrap.nvim` parses the table, measures display cells with
`vim.api.nvim_strwidth()`, allocates the available width, and wraps content
inside each rendered cell.

It is an independent table renderer. It does not fork or patch
`render-markdown.nvim`, and the two can coexist when that plugin's pipe-table
renderer is disabled.

## Requirements And Scope

- Neovim 0.10 or newer.
- No external binaries.
- Built-in filetypes: `markdown`, `md`, `quarto`, `rmd`, and `rmarkdown`.
- Top-level and blockquote-contained GFM-style pipe tables, with or without
  outer pipes. Nested quote depth and each cell's physical Source span are
  preserved.
- GFM alignment rows, including compact single-hyphen delimiters, plus missing
  cells, escaped pipes, and pipes inside matching backtick code spans.
- Mixed CJK/Latin display widths and a documented inline-Markdown display
  subset for table cells.

Currently not supported:

- Pipe tables nested inside list containers. Their continuation indentation is
  deliberately left visible until Source spans can be guaranteed losslessly.
- General Markdown rendering outside tables.
- Implicit repair of malformed/excess-cell tables. Rendering is conservative;
  rendered views show an `⚠ +N excess Source cell(s)` warning, while structural
  editing and structured export refuse the ambiguous table.

## Installation

With `lazy.nvim` or LazyVim:

```lua
return {
  {
    "ice345/markdown-table-wrap.nvim",
    ft = { "markdown", "quarto", "rmd", "rmarkdown" },
    opts = {},
  },
}
```

With the default options, a table-bearing document enters Reader automatically;
plain Markdown stays in Source.

## Everyday Workflow

The plugin exposes three rendered views:

| View | Buffer | Best for |
| --- | --- | --- |
| **Reader** (default) | Protected, unlisted derived buffer | Stable full-document reading, search, rendered selection, and Source-aware cell actions |
| **Inline** | Original Source buffer with extmarks | Editing Source while keeping a nearby rendered table layer |
| **Float** | Disposable table-only window | Focused inspection of the table under the cursor |

In Reader:

- `q` returns to Source and pauses automatic reopening for that buffer.
- `e`, `i`, `a`, `I`, `A`, `o`, and `O` return to the mapped Source position for
  editing. Reader normally reopens after `InsertLeave`.
- `:MarkdownTableToggleInline` returns to Source and enables Inline.
- `:w`, `:wq`, `:x`, and `ZZ` save the backing Source; the Reader is never
  written as a document.
- Native `v`, `V`, and `<C-v>` select real rendered text. Follow with `y` to
  copy the visible Unicode table.

Reader is unlisted, so Bufferline/LazyVim `H` and `L` mappings need explicit
passthrough. These actions are temporary navigation: returning to the Source
restores Reader at the saved cursor and scroll position. A Source that was
explicitly closed or paused stays in Source.

```lua
opts = {
  mappings = {
    reader = { passthrough = { H = "previous_buffer", L = "next_buffer" } },
  },
}
```

Float is temporary: `q`, `<Esc>`, `:MarkdownTableClosePreview`, or the preview
toggle restores the view that opened it. Source returns to Source, Reader is
rebuilt at the same logical cell, and Inline remains active. Refreshing the
Float does not lose that return target.

### Reader Cell Operations

Cell operations always use the exact raw Source span, even when one logical
cell occupies several rendered lines:

| Input | Result |
| --- | --- |
| `yic`, `"ayic` | Yank one raw Source cell using native register rules |
| `vic`, then `y/d/c/p` | Select one logical cell and apply the operation to Source |
| `dic`, `"adic`, `"_dic` | Delete one Source cell without touching its neighbors |
| `cic`, `"acic` | Change one Source cell; deletion and typed insertion form one undo block |
| `.` | Repeat the last successful cell delete/change/put on another cell |
| `c` + another motion | Continue Vim's native change operator in Source; `cip`, `ciw`, `cw`, and `c$` remain available |
| `2yic`, `2dic`, `2cic` | Reject the undefined multi-cell count without changing Source or registers |

Reader reserves Normal-mode `y` and `d` as guarded prefixes for `yic` and
`dic`. A mismatch such as `yj`, `yk`, `dd`, or `dk` cancels safely instead of
copying rendered borders or trying to modify the protected buffer. Use native
Visual selection to copy rendered rows, and use Source for structural edits.

## Common Commands

| Command | Purpose |
| --- | --- |
| `:MarkdownTableToggleReader` | Toggle Reader and Source |
| `:MarkdownTableToggleInline` | Toggle Inline and Source |
| `:MarkdownTableFloatPreview` | Open a table-only float from Source, Inline, or Reader; retain the logical cell and keep the Float authoritative over automatic Reader refreshes |
| `:MarkdownTableEditSource` | Leave Reader and keep Source visible |
| `:MarkdownTableRefresh` | Rebuild the active rendered view |
| `:MarkdownTableEnableAutoPreview` / `:MarkdownTableDisableAutoPreview` | Change the canonical Source policy from Source, Inline, Reader, or Float |
| `:MarkdownTableStatus` | Report the resolved Source policy and current Source/Inline/Reader/Float view |
| `:MarkdownTableToggleInlineViewport` | Toggle the Source-owned Inline viewport option without dismissing Reader or Float |
| `:MarkdownTableHelp` | Show actions and the keys effective in the current view |
| `:MarkdownTableInspect` | Show Source/view, cursor, table, cache, and layout diagnostics |
| `:MarkdownTableNextCell` / `:MarkdownTablePrevCell` | Move by logical cell in Source, Inline, Reader, or Float |
| `:MarkdownTableNextRow` / `:MarkdownTablePrevRow` | Move vertically while retaining the logical column |
| `:MarkdownTableOpen` | Open the URL, file, anchor, wiki link, or image under the cursor |
| `:MarkdownTableYankCell` / `:MarkdownTableYankTable` | Copy semantic cell text or a rendered table |
| `:MarkdownTableExport[!] [tsv\|csv]` | Export the current table, or every table with `!` |

Source editing commands are explicit and form one undo step:

- `:MarkdownTableFormat`
- `:MarkdownTableAddRow`, `:MarkdownTableDeleteRow`
- `:MarkdownTableMoveRowUp`, `:MarkdownTableMoveRowDown`
- `:MarkdownTableAddColumn`, `:MarkdownTableDeleteColumn`
- `:MarkdownTableMoveColumnLeft`, `:MarkdownTableMoveColumnRight`
- `:MarkdownTableToggleAlignment`
- `:MarkdownTableEditCell` (`<C-s>` saves; `Esc` or `q` cancels)

Formatting aligns the raw Markdown Source. Row deletion/movement requires a
body-row cursor; it never interprets a header cursor as the first body row. The
cell editor soft-wraps long Source and grows vertically up to a bounded height.

Rendered copy/export always updates the unnamed and yank registers. System
clipboard integration follows Neovim's `'clipboard'` option; API callers may
force `+`/`*` or disable an additional system-register write.

The complete command and `<Plug>` reference is available in
[`doc/markdown-table-wrap.txt`](doc/markdown-table-wrap.txt).

## Configuration Recipes

### Keep Automatic Reader, Tune Widths

Automatic Reader is the default, so only overrides are necessary:

```lua
opts = {
  min_col_width = 6,
  max_col_width = 40,
  max_width_ratio = 0.95,
  reader = { sticky_header = true },
}
```

### Prefer Inline

```lua
opts = {
  preview_mode = "inline",
  inline_mode = "replace",
  inline_wrap_scope = "always",
}
```

### Render Only On Demand

```lua
opts = {
  auto_preview = false,
}
```

Then use `:MarkdownTableReader`, `:MarkdownTableInlinePreview`, or
`:MarkdownTableFloatPreview`.

### Wide-Table Column Viewport

The default wide-table policy wraps every column. To show a movable contiguous
slice instead:

```lua
opts = {
  wide_table = {
    mode = "viewport",
    viewport = { start_column = 1, column_count = 4, marker = "…" },
  },
}
```

Use `:MarkdownTableViewportLeft` and `:MarkdownTableViewportRight`. Those
commands report that viewport mode is required when the default `"wrap"`
policy is active.

### Coexist With render-markdown.nvim

```lua
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    pipe_table = { enabled = false },
  },
}
```

### Link Safety And Custom Schemes

`http`, `https`, and `mailto` are the default external scheme allowlist. Local
`file:` URIs are resolved and opened inside Neovim. Unknown schemes are refused
unless they are explicitly trusted or handled by a custom resolver:

```lua
opts = {
  link = {
    allowed_schemes = { "http", "https", "mailto", "obsidian" },
    -- resolver = function(target, context, strategy) ... end,
  },
}
```

### Themes

```lua
opts = {
  highlight_preset = "auto", -- or default, tokyonight, catppuccin, render_markdown
  highlights = {
    code = { fg = "#9ece6a" },
    link = { underline = true },
  },
}
```

`theme_dir` may load `<preset>.lua` with `dofile()`. Treat every configured
theme directory as trusted executable Lua, not as a directory for untrusted
downloaded themes.

## Configuration Reference

`setup()` validates values and warns about unknown fixed option names. Dynamic
theme names, highlight keys, link-pattern names, column numbers, and Reader
passthrough keys remain intentionally open.

Calling `setup()` again preserves per-buffer pause, auto-preview, selected
mode, and viewport intent. Use the one-shot `reset_state = true` setup option
only when a full policy reset is desired.

The main option groups are:

| Group | Controls |
| --- | --- |
| top-level width/render options | column sizing, borders, automatic rendering, debounce, and view selection |
| `reader` | automatic opening, wrap, conceal, and sticky header |
| `wide_table` | wrap/viewport policy and per-column constraints |
| `mappings.reader` / `mappings.float` | view-local keys and Reader cell operations |
| `link` | icons, allowed external schemes, custom patterns, and resolver callback |
| `discovery` / `cache` | deterministic discovery backend and derived-model caching |
| `themes` / `highlights` / `theme_dir` | semantic highlight presets and overrides |

For every option and its default, use `:help markdown-table-wrap-configuration`
or read [`doc/markdown-table-wrap.txt`](doc/markdown-table-wrap.txt).

## Integration API

```lua
local table_wrap = require("markdown-table-wrap")

local context = table_wrap.get_state(0)
local config = table_wrap.get_buffer_config(0)
local source_bufnr = table_wrap.resolve_source_buffer(0)
local component = table_wrap.statusline(0) -- e.g. "MTW Reader T2:C2"
table_wrap.action("toggle_reader")
```

Stable normal-mode `<Plug>` mappings use the
`<Plug>(MarkdownTableWrapAction)` form. The plugin emits
`MarkdownTableWrapReaderEnter`, `MarkdownTableWrapReaderLeave`,
`MarkdownTableWrapViewChanged`, and `MarkdownTableWrapRendered` `User` events.
Event data contains only scalar Source/view/window identifiers.

See the Vim help for the complete action and `<Plug>` names.

## Limitations And Troubleshooting

- Inline uses conceal, virtual text, and optional virtual lines. Some terminal
  and wrap combinations can reveal fragments of a long Source row; use
  `inline_wrap_scope = "always"` or Reader for the strictest visual isolation.
- Reader materializes the complete derived document. Very large wrapped tables
  have measurable cold-open cost; see [`docs/performance.md`](docs/performance.md).
- Tree-sitter discovery is optional. `discovery.backend = "auto"` intentionally
  keeps the deterministic Lua scanner until measurements justify otherwise.
- Excess cells remain available in parser metadata, but structured export and
  Source structural editing refuse them rather than silently dropping data;
  rendered views and Inspect show their count.
- Session files should restore Source buffers, not disposable Reader or Float
  buffers.

Useful diagnostics:

```vim
:MarkdownTableInspect
:MarkdownTableHelp
:checkhealth markdown-table-wrap
:help markdown-table-wrap
```

## Development

Run the regression suite from the plugin root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

Contributor invariants and review expectations live in
[`CONTRIBUTING.md`](CONTRIBUTING.md). Test ownership and the release-only manual
matrix live in [`tests/README.md`](tests/README.md). Internal design and scaling
constraints live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## License

MIT. See [`LICENSE`](LICENSE).
