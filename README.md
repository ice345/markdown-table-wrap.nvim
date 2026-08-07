# markdown-table-wrap.nvim

A Neovim/LazyVim plugin for rendering Markdown pipe tables with wrapped cell content.

It does not modify the Markdown source buffer and does not fork or patch `render-markdown.nvim`. It provides three display modes: a stable full-document reader, a source-position-preserving inline overlay, and a floating preview.

## Why

`render-markdown.nvim` makes normal Markdown tables pleasant to read, but very long cell content can still overflow the terminal width. Neovim's normal line wrapping breaks the whole source line, so table borders and columns no longer line up visually.

`markdown-table-wrap.nvim` parses pipe tables, calculates display widths with `vim.api.nvim_strwidth`, allocates columns to fit the current text area, and wraps long content inside each cell.

For documents that use native `wrap`, reader mode is the most robust option. It mirrors the current Markdown document into a protected scratch buffer and replaces every supported top-level pipe table with real Unicode buffer lines. Ordinary prose can still soft-wrap, while long source rows and URLs cannot leak through the rendered table.

## Screenshots

Inline rendering in a Tokyo Night themed Markdown buffer:

![Inline table rendering](docs/01-inline-tokyonight.png)

Viewport scrolling for rendered tables taller than their source table:

<div align="center">
  <video src="https://github.com/user-attachments/assets/5bb6da3d-04f0-4608-8672-f6edfb10f2c4" width="100%"></video>
</div>

Full inline expansion when viewport mode is disabled:

![Full inline rendering](docs/02b-inline-full-toggle.png)

Floating preview for long table reading:

![Floating long table preview](docs/03-floating-long-table.png)

## Features

- Automatic Markdown-only rendering; commands are optional controls.
- Detects supported top-level GFM pipe tables in the current Markdown document.
- Parses header, separator, alignment, and body rows.
- Computes available width from the current window.
- Accounts for number, sign, and fold columns when fitting the table.
- Can shrink below the preferred column width when many columns must fit on screen.
- Wraps long cell content inside each column.
- Supports mixed Chinese, English, and Japanese display widths through `vim.api.nvim_strwidth`.
- Keeps inline code spans intact when they fit; splits only oversized code tokens at display-width-safe character boundaries so narrow panes do not push table borders out of alignment.
- Keeps pipes from splitting table cells when they occur inside matching code spans with arbitrary backtick-run lengths.
- Prefers wrapping at spaces, `、`, `，`, `,`, `；`, `;`, and `/`.
- Renders a Unicode table inline in a replace-like mode.
- Opens a stable rendered reader by default when a supported buffer contains a table; cursor focus is not required.
- Debounces cursor movement and text changes.
- Reveals the Markdown source while typing in Insert mode, then restores the rendered table on `InsertLeave`.
- Skips redraws when the active table content, width, and render options have not changed.
- Avoids re-render scheduling on normal cursor movement when whole-buffer rendering is active.
- Restores window-local `wrap`, `conceallevel`, and `concealcursor` after clearing or leaving Inline replace mode.
- Highlights rendered borders, headers, inline code spans, and Markdown links separately.
- Renders common inline Markdown inside cells to plain display text, including inline code, emphasis, strikethrough, and links.
- Keeps code-wrapped link labels aligned when Markdown conceal hides their backticks.
- Supports `==highlight==`, wiki links, image alt text, and URL-pattern-based link icons.
- Theme presets for Tokyo Night, Catppuccin, a neutral default, and a render-markdown-inspired palette.
- Supports inline custom themes and loading custom theme files from a theme directory.
- Provides source-aware table cell navigation commands.
- Provides inline viewport scrolling for rendered rows that exceed the original source table height.
- Can also render the same table in a floating window.
- Provides a full-document reader that renders every supported table without requiring cursor focus.
- Provides `:MarkdownTableToggleInline` for quickly switching between source and inline rendering.
- Leaves the existing `gx` mapping untouched by default; table-aware source-buffer link handling is opt-in.
- Does not edit the source buffer.
- No external binaries.
- Neovim 0.10+.

## Installation

### GitHub (lazy.nvim / LazyVim)

```lua
return {
  {
    "ice345/markdown-table-wrap.nvim",
    ft = { "markdown", "quarto", "rmd" },
    opts = {},
  },
}
```

If you also use `render-markdown.nvim`, disable its pipe-table renderer as
shown in [Coexisting With render-markdown.nvim](#coexisting-with-render-markdownnvim).

### Local Development And Complete Configuration

Clone or place this directory somewhere on disk, then add:

```lua
-- ~/.config/nvim/lua/plugins/markdown-table-wrap.lua
return {
  {
    dir = "~/Code/lazyvim-table/markdown-table-wrap.nvim",
    ft = { "markdown", "quarto", "rmd" },
    opts = {
      max_width_ratio = 0.9,
      min_col_width = 8,
      max_col_width = 50,
      fit_to_window = true,
      border = "rounded",
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      preview_mode = "reader",
      inline_mode = "replace",
      inline_position = "above",
      dim_source = true,
      auto_preview = true,
      render_all = true,
      auto_preview_in_insert = false,
      clear_on_cursor_leave = true,
      clear_on_insert = true,
      clear_on_visual = true,
      debounce_ms = 80,
      overlay_priority = 10000,
      overlay_fill = true,
      inline_virtual_text = "overlay",
      inline_disable_wrap = true,
      inline_wrap_scope = "cursor",
      inline_viewport_scrolling = false,
      reader = {
        auto_open = "has_table",
        wrap = true,
        linebreak = false,
        breakindent = true,
        conceallevel = 2,
        concealcursor = "nvc",
      },
      highlight_preset = "default",
      theme_dir = nil,
      themes = {},
      extra_filetypes = {},
      highlights = {},
      map_gx = false,
      mappings = {
        reader = {
          enabled = true,
          close = "q",
          edit = "e",
          open_link = "gx",
          help = false,
          insert = { "i", "a", "I", "A", "o", "O" },
          passthrough = {},
        },
        float = {
          enabled = true,
          close = { "q", "<Esc>" },
          open_link = "gx",
          help = false,
        },
      },
      link = {
        icon = "",
        wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
        image = " ",
        resolver = nil,
        custom = {
          github = { pattern = "github", icon = " " },
          gitlab = { pattern = "gitlab", icon = "󰮠 " },
          youtube = { pattern = "youtube", icon = " " },
          bilibili = { pattern = "bilibili", icon = "󰟴 " },
          cern = { pattern = "cern.ch", icon = " " },
        },
      },
    },
    keys = {
      { "<leader>mt", "<cmd>MarkdownTableTogglePreview<cr>", desc = "Toggle Markdown table preview" },
      { "<leader>mp", "<cmd>MarkdownTablePreview<cr>", desc = "Preview Markdown tables" },
      { "<leader>mf", "<cmd>MarkdownTableFloatPreview<cr>", desc = "Float Markdown table preview" },
      { "<leader>mr", "<cmd>MarkdownTableToggleReader<cr>", desc = "Toggle Markdown table reader" },
      { "<leader>mi", "<cmd>MarkdownTableToggleInline<cr>", desc = "Toggle Markdown table inline view" },
      { "<leader>me", "<cmd>MarkdownTableEditSource<cr>", desc = "Edit Markdown source" },
      { "<leader>mc", "<cmd>MarkdownTableClosePreview<cr>", desc = "Close Markdown table preview" },
      { "<leader>mT", "<cmd>MarkdownTableToggleAutoPreview<cr>", desc = "Toggle auto Markdown table preview" },
      { "<leader>mq", "<cmd>MarkdownTableToggleInlineViewport<cr>", desc = "Toggle inline table viewport" },
      { "]c", "<cmd>MarkdownTableNextCell<cr>", desc = "Next table cell" },
      { "[c", "<cmd>MarkdownTablePrevCell<cr>", desc = "Previous table cell" },
      { "]r", "<cmd>MarkdownTableNextRow<cr>", desc = "Next table row" },
      { "[r", "<cmd>MarkdownTablePrevRow<cr>", desc = "Previous table row" },
      { "<leader>mj", function() require("markdown-table-wrap").scroll_view(vim.v.count1) end, desc = "Scroll rendered table down" },
      { "<leader>mk", function() require("markdown-table-wrap").scroll_view(-vim.v.count1) end, desc = "Scroll rendered table up" },
      { "<leader>mgg", "<cmd>MarkdownTableScrollTop<cr>", desc = "Scroll rendered table to top" },
      { "<leader>mG", "<cmd>MarkdownTableScrollBottom<cr>", desc = "Scroll rendered table to bottom" },
    },
  },
}
```

See [ROADMAP.md](ROADMAP.md) for the mode contracts and development order, and
[PUBLISHING.md](PUBLISHING.md) for the release flow.

## Default Behavior

Reader mode is the default preview strategy. With `auto_preview = true` and
`reader.auto_open = "has_table"` (the default), a supported buffer switches to
the protected Reader only after at least one table is detected. Plain Markdown
documents remain in Source. Set `reader.auto_open = "always"` to retain the
earlier behavior of opening Reader for every supported buffer.

Reader contains the complete document and fully rendered tables. No table needs
cursor focus, and the source buffer remains untouched in the background.
Reader protects those finished table rows from being interpreted as Markdown a
second time. Characters such as `_` and `<...>` inside rendered code therefore
remain literal and cannot shift a wrapped border, while search and yank still
operate on the real rendered lines underneath the display layer.

The default interaction model is:

- Normal mode stays in Reader and shows the rendered document.
- `v`, `V`, and `<C-v>` select real Reader lines. Yanked text is exactly the rendered content, and the view remains in Reader after copying.
- `i`, `a`, `I`, `A`, `o`, and `O` switch to the mapped source line for editing. Reader reopens after `InsertLeave`.
- `:w`, `:wq`, `:x`, and `ZZ` save the backing Markdown source directly. The rendered buffer itself is never written to disk; `:wq` then quits as usual.
- `:MarkdownTableToggleReader` switches between Reader and Source. Closing Reader pauses automatic reopening until the command is run again.
- `:MarkdownTableEditSource` leaves Reader and keeps Source visible for a longer editing session.
- `gx` opens the original URL under a rendered link.

### Choosing A View

Use Source when editing Markdown structure. It is the safest view for `dd`,
Visual changes, moving rows, changing delimiters, and other operations where
you need every source line to be a real Markdown line.

Use Inline when you want to edit the original buffer while seeing rendered
tables. The source buffer remains active, but conceal and virtual text are
visual layers, so Source is preferable for large structural edits.

Use Reader when you want a stable, complete reading view. Reader renders the
whole document in a separate protected buffer, and `i`/`a`/`o` or `e` temporarily
returns to the mapped Source line for editing.

`<leader>mi` can be mapped to `:MarkdownTableToggleInline`:

```lua
{ "<leader>mi", "<cmd>MarkdownTableToggleInline<cr>", desc = "Toggle Markdown table inline view" }
```

The command enables Inline from Source or Reader. Pressing it again clears the
Inline layer and leaves Source visible. Use `:MarkdownTableReader` or your
Reader keymap when you want to return to the full-document reading view.

The commands can be bound like ordinary LazyVim keys:

```lua
keys = {
  { "<leader>mr", "<cmd>MarkdownTableToggleReader<cr>", desc = "Toggle Markdown reader/source" },
  { "<leader>mi", "<cmd>MarkdownTableToggleInline<cr>", desc = "Toggle Markdown table inline view" },
  { "<leader>me", "<cmd>MarkdownTableEditSource<cr>", desc = "Edit Markdown source" },
}
```

`preview_mode = "reader"` selects the default strategy. `MarkdownTableToggleReader`
changes the current window between Reader and Source, while
`MarkdownTableToggleInline` selects Inline for the current editing session.

Session files should restore the canonical Source buffer, not the disposable
Reader or Float scratch buffer. After plugin setup, normal `auto_preview` and
`reader.auto_open` policy may recreate the selected view; the plugin does not
serialize scratch view buffers into the session.

### Read, Edit, Inspect, Troubleshoot

For daily use, five actions cover the normal workflow:

- Read: `:MarkdownTableToggleReader` opens or closes the stable full-document
  projection.
- Edit: `:MarkdownTableEditSource` returns to the canonical Markdown buffer.
- Follow: `:MarkdownTableOpen` opens the target under the cursor relative to
  the Source file; split, vertical-split, and tab variants are also available.
- Inspect: `:MarkdownTableInspect` reports the active mode, Source/view
  identity, cursor mapping, table/cell, width budget, cache, and options.
- Learn: `:MarkdownTableHelp` shows the configured view keys and command-based
  exit path, including when local Reader mappings are disabled.

Reader copies rendered Unicode lines; Source and Inline copy the original
Markdown. Reader search operates on rendered text. File navigation and buffer
transitions resolve back to Source, while structural edits should be performed
in Source.

### Why Reader Avoids Wrap Leaks

Inline replacement is tied to real source rows. When a raw Markdown table row is wider than the window and `wrap` is enabled, Neovim may create continuation screen rows underneath the extmark overlay. Conceal and virtual text cannot reliably replace those continuation rows on every terminal, which is why source fragments such as an extra `|` can appear.

Reader mode is already the default strategy. The equivalent explicit
configuration is:

```lua
require("markdown-table-wrap").setup({
  preview_mode = "reader",
  auto_preview = true,
  fit_to_window = true,
  reader = {
    auto_open = "has_table",
    wrap = true,
    linebreak = false,
    breakindent = true,
  },
})
```

Press `e`, `q`, or run `:MarkdownTableEditSource` to leave reader mode and keep the source visible. To copy the original Markdown syntax instead of rendered text, toggle to Source first and use Visual mode there.

### Coexisting With render-markdown.nvim

Use `render-markdown.nvim` for the rest of Markdown, but disable its table renderer so this plugin owns pipe tables:

```lua
-- ~/.config/nvim/lua/plugins/render-markdown.lua
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    pipe_table = {
      enabled = false,
    },
  },
}
```

## Commands

You do not need commands for normal use. With `auto_preview = true`, Reader
opens automatically when a supported buffer contains a table and renders every
supported table. The commands below provide manual control and access to the optional
inline and floating modes.

- `:MarkdownTablePreview` opens the configured preview mode. By default this is Reader.
- `:MarkdownTableInlinePreview` renders an inline preview for the table under the cursor.
- `:MarkdownTableFloatPreview` opens a floating preview for the table under the cursor.
- `:MarkdownTableReader` opens the full document in the rendered reader.
- `:MarkdownTableToggleReader` switches the current window between Reader and Source.
- `:MarkdownTableToggleInline` switches between Source and Inline. From Reader it first returns to Source.
- `:MarkdownTableEditSource` leaves Reader, pauses automatic reopening, and keeps Source visible.
- `:MarkdownTableTogglePreview` toggles the active preview.
- `:MarkdownTableClosePreview` closes the preview.
- `:MarkdownTableRefresh` force refreshes rendered tables in the current Markdown buffer.
- `:MarkdownTableEnableAutoPreview` enables automatic preview in the current buffer.
- `:MarkdownTableDisableAutoPreview` disables automatic preview in the current Source buffer. When run in Reader, it targets the backing Source buffer.
- `:MarkdownTableToggleAutoPreview` toggles automatic preview in the current buffer; disabling it from Reader targets the backing Source buffer.
- `:MarkdownTableToggleInlineViewport` toggles between viewport-sliced inline rendering and full inline rendering.
- `:MarkdownTableStatus` shows the current auto-preview state.
- `:MarkdownTableNextCell` moves to the next source cell in the current table row.
- `:MarkdownTablePrevCell` moves to the previous source cell in the current table row.
- `:MarkdownTableNextRow` moves to the same source cell in the next table row.
- `:MarkdownTablePrevRow` moves to the same source cell in the previous table row.
- `:MarkdownTableOpen` opens the target under the cursor from Source, Inline,
  Reader, or Float. Relative paths are based on the Source file.
- `:MarkdownTableOpenSplit`, `:MarkdownTableOpenVSplit`, and
  `:MarkdownTableOpenTab` open file targets in the requested layout.
- `:MarkdownTableOpenLink` is the compatibility alias for
  `:MarkdownTableOpen`.
- `:MarkdownTableInspect` shows active Source/view diagnostics suitable for a
  bug report.
- `:MarkdownTableHelp` shows common actions and configured view keys.
- `:MarkdownTableScrollDown` scrolls the rendered table view down without moving through source rows.
- `:MarkdownTableScrollUp` scrolls the rendered table view up without moving through source rows.
- `:MarkdownTableScrollTop` jumps the rendered table viewport to the top.
- `:MarkdownTableScrollBottom` jumps the rendered table viewport to the bottom.

Press `q` inside Reader to return to Source, or inside the floating preview window to close the float.

Reader provides table-aware `gx` for rendered links and delegates ordinary
positions to the Source mapping captured when Reader opens. In Source buffers,
`map_gx = false` by default, so the plugin does not replace your existing `gx`
mapping. Run `:MarkdownTableOpen` directly, add your own keymap, or set
`map_gx = true` to opt into the buffer-local table-aware mapping. The command
supports URLs, relative/absolute files, anchors, wiki links, images, and
multiple targets.

## Configuration

```lua
require("markdown-table-wrap").setup({
  max_width_ratio = 0.9,
  min_col_width = 8,
  max_col_width = 50,
  fit_to_window = true,
  border = "rounded",
  use_unicode_border = true,
  table_border = "rounded",
  row_separator = true,
  preview_mode = "reader",
  inline_mode = "replace",
  inline_position = "above",
  dim_source = true,
  auto_preview = true,
  render_all = true,
  auto_preview_in_insert = false,
  clear_on_cursor_leave = true,
  clear_on_insert = true,
  clear_on_visual = true,
  debounce_ms = 80,
  overlay_priority = 10000,
  overlay_fill = true,
  inline_virtual_text = "overlay",
  inline_disable_wrap = true,
  inline_wrap_scope = "cursor",
  inline_viewport_scrolling = false,
  reader = {
    auto_open = "has_table",
    wrap = true,
    linebreak = false,
    breakindent = true,
    conceallevel = 2,
    concealcursor = "nvc",
  },
  highlight_preset = "default",
  theme_dir = nil,
  themes = {},
  extra_filetypes = {},
  highlights = {},
  map_gx = false,
  mappings = {
    reader = {
      enabled = true,
      close = "q",
      edit = "e",
      open_link = "gx",
      help = false,
      insert = { "i", "a", "I", "A", "o", "O" },
      passthrough = {},
    },
    float = {
      enabled = true,
      close = { "q", "<Esc>" },
      open_link = "gx",
      help = false,
    },
  },
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    resolver = nil,
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
})
```

Options:

- `max_width_ratio`: maximum preview table width as a ratio of the current window width, clamped to `0.1` through `1.0`.
- `min_col_width`: minimum content width for each column.
- `max_col_width`: maximum natural content width before wrapping.
- `fit_to_window`: prioritize fitting the complete table inside the current text area, even when this requires columns narrower than `min_col_width`.
- `border`: floating window border style.
- `use_unicode_border`: use Unicode table drawing characters. Set to `false` for ASCII.
- `table_border`: `"rounded"` or `"single"` for rendered table corners.
- `row_separator`: draw horizontal separators between body rows for clearer cell grouping.
- `preview_mode`: `"reader"` (default), `"inline"`, or `"float"` for `:MarkdownTablePreview`.
- `reader`: behavior for the protected full-document reader. `reader.auto_open = "has_table"` opens it automatically only when a table is detected; use `"always"` to open it for every supported buffer. Reader windows enable `wrap` and `breakindent` while keeping `linebreak` disabled by default.
- `inline_mode`: `"replace"` or `"insert"`. Replace mode hides source text and overlays the rendered table in place.
- `inline_position`: `"above"` or `"below"` for insert mode.
- `dim_source`: dim the original Markdown table lines while insert mode is active.
- `auto_preview`: automatically render supported buffers. In Reader mode, automatic opening also follows `reader.auto_open`.
- `render_all`: render all Markdown tables in the current buffer instead of only the cursor table.
- `auto_preview_in_insert`: keep replacement rendering active while typing in Insert mode.
- `clear_on_cursor_leave`: clear inline rendering when the cursor leaves a table or window.
- `clear_on_insert`: reveal source Markdown while editing, then re-render on `InsertLeave`.
- `clear_on_visual`: in inline mode, reveal source Markdown while selecting text, then re-render after leaving Visual mode. Reader mode selects its real rendered lines directly.
- `debounce_ms`: delay before automatic refresh after movement or text changes.
- `overlay_priority`: extmark priority used to cover other renderers such as `render-markdown.nvim`.
- `overlay_fill`: fill the rest of each rendered source line with blank overlay text so long source rows do not leak past the rendered table.
- `inline_virtual_text`: `"overlay"` or `"win_col"` for the replace-mode virtual text strategy. The default `"overlay"` is the more portable path.
- `inline_disable_wrap`: temporarily set `nowrap` in windows showing inline replace mode so long source rows do not soft-wrap underneath the rendered table.
- `inline_wrap_scope`: controls where `inline_disable_wrap` applies. `"always"` keeps the window-wide `nowrap` behavior, `"cursor"` (the default) disables wrapping only while the cursor is inside a rendered table, and `"never"` leaves `wrap` fully under user control.
- `inline_viewport_scrolling`: when `true`, `:MarkdownTableScrollDown` and `:MarkdownTableScrollUp` page through rendered rows inside the original table height. The default is `false`, which shows the complete rendered table inline with extra virtual lines.
- `highlight_preset`: `"default"`, `"tokyonight"`, `"catppuccin"`, `"render_markdown"`, `"auto"`, or any custom key supplied through `themes`/`theme_dir`. The default preset follows standard Neovim highlight groups so it fits arbitrary colorschemes without extra theme tuning.
- `theme_dir`: optional directory containing custom theme files named `<preset>.lua`; the file name must match `highlight_preset`.
- `themes`: inline custom theme table keyed by `highlight_preset`.
- `highlights`: override highlight specs by semantic key.
- `map_gx`: opt into a buffer-local `gx` mapping for table links in Source buffers. It defaults to `false`, leaving the user's existing mapping untouched; Reader links remain directly openable.
- `mappings`: configure or disable Reader/Float local mappings. Set
  `mappings.reader = false` to install no Reader-local mappings; commands and
  `<Plug>` actions remain available. `mappings.reader.passthrough` accepts a
  stable action name or `{ policy = "leave" | "source" | "view" }` for an
  explicitly captured Source mapping.
- `link`: icon configuration plus an optional `resolver(target, context,
  strategy)` callback. Return `true`/`"noop"` when handled, `false` to cancel,
  or `"edit"`, `"split"`, `"vsplit"`, or `"tab"` to choose built-in file
  opening.
- `extra_filetypes`: list of additional filetypes to enable table rendering for. The default is `{}`, meaning the built-in `markdown`, `md`, `quarto`, `rmd`, and `rmarkdown` filetypes render tables.

Reader navigation example without replacing Source mappings globally:

```lua
require("markdown-table-wrap").setup({
  mappings = {
    reader = {
      passthrough = {
        H = "previous_buffer",
        L = "next_buffer",
        gf = "open",
      },
    },
  },
})
```

Named actions leave Reader safely when a real buffer transition is required.
To delegate a custom Source mapping instead, use for example
`K = { policy = "source" }` or `K = { policy = "leave" }`.

```lua
require("markdown-table-wrap").setup({
  extra_filetypes = { "text" },
})
```

> **Note for LazyVim users:** If you add extra filetypes, you must also include them in the plugin's `ft` list to load the plugin for those filetypes:
>
> ```lua
> return {
>   {
>     "ice345/markdown-table-wrap.nvim",
>     ft = { "markdown", "quarto", "rmd", "text" },
>     opts = {
>       extra_filetypes = { "text" },
>     },
>   },
> }
> ```

Highlight override example:

Semantic highlight groups are reapplied after `:colorscheme` changes. A direct
spec such as `{ fg = "#7aa2f7" }` replaces the preset's linked base for that
semantic key.

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "default",
  highlights = {
    border = { fg = "#7aa2f7" },
    code = { fg = "#9ece6a" },
    bold = { fg = "#e0af68", bold = true },
    italic = { fg = "#7aa2f7", italic = true },
    strike = { fg = "#f7768e", strikethrough = true },
    mark = { fg = "#1a1b26", bg = "#e0af68" },
    link = { fg = "#7dcfff", underline = true },
  },
})
```

Custom theme example:

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "my_theme",
  themes = {
    my_theme = {
      border = { fg = "#89b4fa" },
      inline = { fg = "#cdd6f4" },
      source = { link = "Comment" },
      header = { fg = "#f9e2af", bold = true },
      code = { fg = "#a6e3a1" },
      link = { fg = "#89dceb", underline = true },
      wiki_link = { fg = "#cba6f7", underline = true },
      image = { fg = "#94e2d5" },
      bold = { fg = "#f9e2af", bold = true },
      italic = { fg = "#cba6f7", italic = true },
      strike = { fg = "#f38ba8", strikethrough = true },
      mark = { fg = "#1e1e2e", bg = "#f9e2af" },
      blank = {},
    },
  },
})
```

Theme directory example:

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "my_theme",
  theme_dir = vim.fn.stdpath("config") .. "/markdown-table-wrap-themes",
})
```

Then create `~/.config/nvim/markdown-table-wrap-themes/my_theme.lua` returning the same table shape.

Link icon example:

```lua
require("markdown-table-wrap").setup({
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
})
```

Standard Markdown links use `[text](url)`. The plugin also accepts `(text)[url]` as a convenience form inside table cells.

Semantic highlight keys:

- `border`
- `inline`
- `source`
- `header`
- `code`
- `link`
- `wiki_link`
- `image`
- `bold`
- `italic`
- `strike`
- `mark`
- `blank`

Content highlight keys are background-transparent when they only link to an
existing highlight group. This prevents Inline replace mode from turning each
cell into a filled rectangle when `Normal`, `Title`, or another linked group
has a colorscheme background. Add an explicit `bg` to a semantic key when a
filled background is intentional; `blank` is only the padding highlight and
can usually be left as `{}`.

## Lua API

The inspection helpers expose effective buffer-local state without changing it:

```lua
local table_wrap = require("markdown-table-wrap")

local config = table_wrap.get_buffer_config(0)
local mode = table_wrap.get_preview_mode(0)
local context = table_wrap.get_state(0)
local source_bufnr = table_wrap.resolve_source_buffer(0)
local component = table_wrap.statusline(0)
```

- `get_buffer_config(bufnr?)` returns a deep-copied effective configuration for
  the buffer, including runtime view, auto-preview, and inline-viewport
  overrides. Omit `bufnr` or pass `0` for the current buffer.
- `get_preview_mode(bufnr?)` returns the buffer's effective `"reader"`,
  `"inline"`, or `"float"` mode without mutating global setup.
- `get_state(bufnr?)` returns a deep-copied active context containing the mode,
  canonical Source, view/window, mapped cursor, table/cell, cache, and effective
  configuration.
- `resolve_source_buffer(bufnr?)` returns the canonical Source buffer behind a
  Reader or Float.
- `action(name, opts?)` runs the same stable action used by commands and
  `<Plug>` mappings. See `require("markdown-table-wrap.actions").names()` for
  the current set.
- `statusline(bufnr?)` returns a compact string such as `MTW Reader T3:C2`, or
  an empty string when no valid context exists.

Stable normal-mode `<Plug>` mappings follow the
`<Plug>(MarkdownTableWrapAction)` form. Actions are `ToggleReader`,
`ToggleInline`, `EditSource`, `Close`, `Refresh`, `Open`, `OpenSplit`,
`OpenVSplit`, `OpenTab`, `NextBuffer`, `PreviousBuffer`, `AlternateBuffer`,
`SplitSource`, `VSplitSource`, `TabSource`, `Inspect`, and `Help`.

The plugin emits `User` events named `MarkdownTableWrapReaderEnter`,
`MarkdownTableWrapReaderLeave`, `MarkdownTableWrapViewChanged`, and
`MarkdownTableWrapRendered`. On Neovim versions that support event data,
`args.data` contains primitive Source/view buffer and window identifiers.

## Example

With the default configuration, opening a Markdown file renders this table automatically. You can also run `:MarkdownTablePreview` manually:

| 名称 | 说明 | 路径 |
| --- | --- | --- |
| Rc | `Rc<RefCell<T>>` 常用于需要共享所有权并且在运行时检查可变借用的场景，尤其适合写解释器、树结构、图结构。 | `notes/01-smart-pointers.md` |
| render-markdown.nvim | 当表格某一列非常长，Neovim 原生 wrap 会把整行硬折断，导致边框和列对齐错乱。 | lua/plugins/render-markdown.lua |

## Current Scope

The current rendering model includes:

- Full-document Reader preview by default.
- Automatic rendering of every supported table without cursor focus.
- Command-free workflow: edit Source in Insert mode and view rendered content in Normal mode.
- Visual selection of real Reader lines, with Reader retained after yank.
- Cached refreshes to avoid unnecessary redraw flicker.
- Window-local conceal handling with restoration on clear.
- Semantic highlights for borders, headers, inline code, and links.
- Background-transparent linked content highlights prevent filled Inline cells
  unless an explicit `bg` is configured.
- Code-wrapped link labels keep concealed delimiters out of width calculation
  so Inline separators remain aligned.
- Cell navigation commands that understand inline code pipes like `` `a|b` ``.
- Floating preview is retained for focused table-only inspection.
- Top-level GFM pipe-table parsing with conservative Markdown block boundaries.
- Inline code spans stay intact when they fit and split only when an oversized
  token would exceed its allocated display width.
- Escaped pipes are displayed as `|`.
- A headless Neovim regression suite exists in `tests/run.lua`.
- Tests are split by parser, Markdown, width, rendering, modes, lifecycle,
  multi-window context, actions, links, mappings, inspection, configuration,
  and the system render chain. See [tests/README.md](tests/README.md) for the
  coverage map and release-only manual checks.

## Testing

Run the current regression suite from the repository root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

The suite currently covers:

- GFM-style pipe tables with optional outer pipes.
- Escaped pipes and pipes inside inline code.
- Multi-backtick inline code spans with internal pipes.
- Table-shaped text inside backtick- and tilde-fenced code blocks.
- Alignment rows and missing/extra cells.
- GFM Example 202-style body rows without literal pipes and top-level tables
  indented by up to three spaces.
- Conservative termination at headings, lists, blockquotes, thematic breaks,
  HTML blocks, link definitions, and other new block-level structures.
- Adjacent pipe-like prose that must not be concealed as part of a table.
- Single-read parser behavior for large runs of invalid pipe-shaped prose.
- Mixed CJK/English width and hard breaks.
- Width helpers and display-width-aware padding.
- Inline token highlighting through wrapping, floating preview, and inline replacement.
- Link icons, `==highlight==`, inline custom themes, and theme-directory loading.
- Whole-buffer automatic rendering through Neovim extmarks.
- Compact continuous-border highlight spans and colorscheme highlight replay.
- Full-document reader replacement, source preservation, link navigation, and fit-to-window behavior.
- Reader refresh, anonymous-buffer save errors, and source-save forwarding through `:w` and `:x`.
- Source-aware cell navigation, configuration validation, and opt-in table-aware `gx` installation when a filetype pre-dates plugin setup.
- Buffer-local deferred refresh, view/auto/viewport state, option restoration,
  and wipeout cleanup.

When running from the parent development directory, use:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=./markdown-table-wrap.nvim" \
  -c "luafile markdown-table-wrap.nvim/tests/run.lua" \
  -c "qa!"
```

## Healthcheck

```vim
:checkhealth markdown-table-wrap
```

The report includes the active Source/view context, resolver and mapping
policy, theme, module loading, and `render-markdown.nvim` coexistence hint.

## Help

```vim
:help markdown-table-wrap
```

Use `:MarkdownTableHelp` for a short in-editor action overlay and
`:MarkdownTableInspect` for context suitable for issue reports.

The default Reader uses real lines in a separate protected scratch buffer. Optional inline mode hides source table text with extmark conceal and overlays rendered rows on the original table rows. Neither mode edits the Markdown source.

With `inline_viewport_scrolling = false`, the complete rendered table is shown inline by default, even when wrapped cells make it taller than the source table. This is easier to understand when first trying the plugin because there is no hidden rendered content.

Enable `inline_viewport_scrolling = true` or use `:MarkdownTableToggleInlineViewport` when you prefer a scrollable visual slice inside the original source table height. In viewport mode, `:MarkdownTableScrollDown` and `:MarkdownTableScrollUp` page through the rendered table slice. In full inline mode, those commands fall back to normal window scrolling because the full rendered table is already visible as virtual lines.

## Platform Notes

Inline replacement is built on Neovim extmarks, conceal, overlay virtual text, and optional virtual lines. That stack is consistent logically, but terminals and platforms can expose different visual edge cases when the original Markdown source line is longer than the window.

Inline mode includes cross-platform hardening through `inline_virtual_text = "overlay"` and `inline_disable_wrap = true`. A concealed source row can still soft-wrap into extra screen lines on some terminal and platform combinations when cursor-scoped wrapping restores `wrap`; this can reveal fragments of the original Markdown. Use `inline_wrap_scope = "always"` for the strictest inline stability, or use reader mode to keep native prose wrapping without relying on conceal over soft-wrapped source rows.
## Project Structure

```text
markdown-table-wrap.nvim/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   └── feature_request.yml
│   ├── pull_request_template.md
│   └── workflows/
│       └── ci.yml
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── PUBLISHING.md
├── README.md
├── ROADMAP.md
├── doc/
│   ├── markdown-table-wrap.txt
│   └── tags
├── docs/
│   ├── 01-inline-tokyonight.png
│   ├── 02-inline-scroll.gif
│   ├── 02b-inline-full-toggle.png
│   └── 03-floating-long-table.png
├── lua/
│   └── markdown-table-wrap/
│       ├── actions.lua
│       ├── context.lua
│       ├── events.lua
│       ├── health.lua
│       ├── init.lua
│       ├── inline.lua
│       ├── inspect.lua
│       ├── links.lua
│       ├── mappings.lua
│       ├── markdown.lua
│       ├── nav.lua
│       ├── parser.lua
│       ├── reader.lua
│       ├── render.lua
│       ├── theme.lua
│       ├── types.lua
│       ├── width.lua
│       └── wrap.lua
├── plugin/
│   └── markdown-table-wrap.lua
├── stylua.toml
└── tests/
    ├── README.md
    ├── helpers.lua
    ├── run.lua
    └── spec/
        ├── actions_spec.lua
        ├── config_spec.lua
        ├── context_spec.lua
        ├── inline_spec.lua
        ├── inspect_spec.lua
        ├── lifecycle_spec.lua
        ├── links_spec.lua
        ├── mappings_spec.lua
        ├── markdown_spec.lua
        ├── mode_spec.lua
        ├── multiwindow_spec.lua
        ├── nav_spec.lua
        ├── parser_spec.lua
        ├── reader_spec.lua
        ├── render_spec.lua
        ├── system_spec.lua
        ├── theme_spec.lua
        ├── width_spec.lua
        └── wrap_spec.lua
```

## License

MIT
