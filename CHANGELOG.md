# Changelog

All notable changes to `markdown-table-wrap.nvim` are documented here.

## 0.7.0 - Cross-View Reliability And Blockquote Tables

### Added

- Render top-level and nested blockquote pipe tables in Reader, Inline, and
  Float while retaining visible quote depth and exact physical Source spans for
  cells and inline tokens. Reader `yic`/`dic`/`cic`, navigation, links, and the
  explicit table formatter all remain Source-correct across quote-spacing
  variants; list-contained tables stay conservatively unsupported.
- Add a shared tolerant UTF-8 iterator plus structural pipe, backtick-code,
  fence, and container scanners. Discovery, parsing, navigation, wrapping, and
  rendering now use one byte-column contract.
- Add `link.allowed_schemes`, defaulting to `http`, `https`, and `mailto`.
  Local `file:` URIs open inside Neovim; remote file hosts and untrusted schemes
  are refused unless a custom resolver handles them.
- Add setup-time diagnostics for unknown fixed option names and the one-shot
  `reset_state = true` control for intentionally clearing per-buffer policy.
- Show excess Source-cell counts in Reader/Inline/Float, context, Inspect, and
  health output before structural edits or structured exports refuse the
  ambiguous table.

### Changed

- Keep automatic Reader as the default. Repeated `setup()` calls now preserve
  explicit per-buffer pause, automatic-preview, selected-view, and viewport
  intent unless `reset_state = true` is supplied.
- Make public preview, status, automatic-preview, Inline-viewport, navigation,
  and wide-table viewport commands resolve Reader and Float through their
  canonical Source buffer.
- Make Float a reversible view transition: `q`, `<Esc>`, close, and toggle
  restore the originating Source, Reader, or Inline view; Reader returns to the
  same logical cell, including after a Float refresh.
- Format against raw Markdown display width, preserve blockquote containment,
  refuse row deletion/movement from a header, and give the isolated cell editor
  bounded soft-wrapped growth.
- Follow Neovim's `'clipboard'` option for copy/export system-register writes,
  prefer additional CJK sentence punctuation as wrap boundaries, and expand
  LuaLS types, health checks, contributor guidance, performance diagnostics,
  and the concise README contract.

### Fixed

- Accept compact GFM delimiter cells containing one or more hyphens, with the
  same rule shared by discovery and parsing; continue scanning a candidate
  range when an earlier table-like block is structurally rejected.
- Preserve Reader and Inline cursor/scroll views across native or configured
  temporary buffer navigation. Reader snapshots are per Source/window and are
  discarded after Source cursor, scroll, or content changes; explicit close
  still pauses and returns to Source.
- Make next/previous/alternate/selected-buffer actions leave Reader or Float
  without recording an explicit pause, so passthrough `H`/`L` returns to the
  mode from which navigation began.
- Route Reader, native-fallback, and standalone Float link opening through the
  external-scheme policy; expand `~/` paths from `HOME` without Vim command
  substitution.
- Clear Float ownership on external window close and Source/Float wipeout, and
  send Reader/Float scroll commands as real control-key termcodes.
- Prevent a queued automatic Reader refresh from immediately replacing a Float
  opened from Reader through a real leader mapping.
- Keep Float navigation and hidden-column viewport movement on logical cells,
  and map the Float cursor back to the exact Source cell for context and links.
- Avoid repeated configuration/theme deep work and unchanged `WinScrolled`
  refresh scheduling; internal read-only cache paths retain public isolated-copy
  behavior and substantially reduce unchanged Reader refresh allocation.
- Exclude help and cell-editor scratch buffers from automatic preview, preserve
  user policy during setup re-entry, and clean all new buffer-owned state on
  wipeout.

## 0.6.0 - Reader Semantics And Lifecycle Hardening

### Fixed

- Guard Reader's `y` and `d` cell prefixes so mistyped motions such as
  `yj`/`yk` cannot yank rendered borders and `dj`/`dk`/`dd` cannot raise E21;
  cancellation preserves the cursor, registers, Reader, and Source.
- Make Reader `cic` leave and revalidate the canonical Source before clearing
  the cell, so a failed Reader transition or concurrent Source change cannot
  apply a partial or stale edit.
- Delegate `yic`, `dic`, and `cic` to native operations on the exact Source
  span so selected registers, the small-delete register, black-hole behavior,
  and one-step change undo match Neovim.
- Make logical `vic` selections route `y`, `d`, `c`, `p`, and `P` to the raw
  Source cell while preserving native rendered Visual selections and restoring
  existing Visual mappings.
- Add changedtick-guarded Reader `.` repeat for cell delete/change/put and
  reject unsupported multi-cell counts without mutating Source.
- Stop mapping `cip` by default so native `ci` paragraph remains available;
  add `:MarkdownTablePutCell` and `<Plug>(MarkdownTableWrapPutCell)`, while
  retaining `mappings.reader.cell.put = "cip"` as an explicit opt-in.
- Keep Reader `c` as a native Source change-operator prefix instead of eagerly
  changing the current cell. `cic` remains the logical-cell operation, while
  `cip`, `ciw`, `cw`, and other motions continue with their native meaning.
- Preserve logical cell `.` repeat when undo followed by redo returns to the
  recorded undo sequence; unrelated Source changes still invalidate it.
- Keep Reader cell, link, context, fallback, and rendered-copy actions on
  narrow snapshots instead of deep-copying the complete rendered document;
  refocus changed cells through the existing logical-cell index.
- Roll back failed Reader projection updates to the previous lines, indexes,
  changedtick, and protected buffer state; failed Reader opens now release
  Source `bufhidden` ownership and delete their disposable scratch buffer.
- Contain and report unexpected scheduled-refresh failures, and make resize
  events refresh every affected visible Reader instead of only the current
  buffer.

### Changed

- Move configuration defaults/normalization and command/`<Plug>` registration
  into focused modules. `init.lua` retains public API, per-Source policy,
  scheduling, and cross-view lifecycle orchestration.

## 0.5.1 - Reader Cell Text-Object Fixes

### Fixed

- Resolve `yic`, `dic`, and `vic` through Vim's operator-pending and Visual
  text-object phases so real keyboard input is not shadowed by built-in
  operators.
- Keep `vic` selections aligned to each rendered segment's byte range, so CJK
  text, wide link icons, and UTF-8 length differences cannot highlight or yank
  a neighboring `│` border.
- Make `vic` followed by `y` copy only the selected rendered logical cell and
  restore any user-defined Visual-mode `y` mapping after the selection ends.
- Add regression coverage for the CrossOver/Proton/Wine/Parallels-style table,
  links, inline code, CJK wrapping, typed `yic`/`dic`/`vic`, and mapping
  restoration.

## 0.5.0 - Table Workbench

### Added

- Add Source-aware Reader cell mappings: `yic` copies the original Markdown
  cell source, `vic` selects a logical cell across wrapped rendered lines,
  `dic` clears one cell without rewriting the row, `cic` clears and enters
  Source Insert, `cip` replaces a cell from the unnamed register, and `c`
  delegates to the same cell change behavior with a safe Source/native
  fallback outside cells.
- Keep native Reader `v`/`V`/`<C-v>` behavior while adding a higher-priority
  Visual overlay so selections remain visible on rendered table cells.
- Add semantic rendered-cell and rendered-table copy actions plus
  `:MarkdownTableExport[!] [tsv|csv]`. Rendered copy omits Markdown syntax and
  decorative icons; TSV/CSV export keeps delimiters and quotes structurally
  safe without mutating Source.
- Add opt-in `wide_table` column policies with fixed/min/max/weight/priority
  rules, deterministic overflow metadata, and a marker-based horizontal column
  viewport with left/right commands.
- Add optional Reader sticky headers and an indexed logical-cell map so cursor
  updates remain bounded for large rendered documents.
- Add an explicit Source editing companion for table formatting, row/column
  add/delete/move, alignment cycling, and focused long-cell popup editing.
  Every rewrite is validated, one undo step, and refuses excess-cell tables
  without a partial change; automatic rendering remains read-only.

## 0.4.0 - Exact Metadata, GFM Correctness, And Performance

### Added

- Add a pure line-array parser API and annotated table, row, cell, delimiter,
  token, and Source-span models. Wrapped rendered cell segments retain stable
  table/row/column identity and best-available Source byte ranges.
- Replace pattern-only inline display parsing with source/render-spanned tokens
  supporting arbitrary backtick runs, balanced-parenthesis destinations,
  reference links, autolinks, nested emphasis, images, wiki links, and hard
  breaks while leaving unsupported syntax visible.
- Add an attributed GFM fixture corpus with explicit supported, invalid, and
  deliberately unsupported classifications.
- Add inspectable `auto`, `lua`, and optional `treesitter` discovery backends.
  Explicit Tree-sitter discovery falls back safely; `auto` keeps the guaranteed
  Lua scanner until benchmarks justify changing the default.
- Add changedtick-aware parse and discovery caching plus window/config-aware
  layout caching, cleanup diagnostics, and documented performance benchmarks.

### Changed

- Treat native buffer/window navigation away from Reader as temporary view
  loss instead of explicit Source pause. Returning to an auto-preview Source
  containing a table now restores Reader; explicit close/edit/toggle actions
  continue to set `paused=true`.
- Consolidate Reader table concealment and fully highlighted overlay into one
  extmark per rendered line, removing redundant range highlights from large
  full-document Readers.
- Extend `:MarkdownTableInspect` and `:checkhealth markdown-table-wrap` with
  discovery backend, fallback, cache-stage, hit/miss, and token-cache details.

### Fixed

- Prevent Reader tables from being parsed a second time by Markdown syntax or
  third-party renderers. Inline-code underscores and angle brackets now keep
  their literal display width and semantic code styling, so narrow wrapped
  cells cannot move vertical borders; the real rendered lines remain available
  for search, selection, and yank.

## 0.3.0 - Transparent Modes And Neovim Integration

### Added

- Add a mode-agnostic context API with `get_state(bufnr?)`,
  `resolve_source_buffer(bufnr?)`, `action(name, opts?)`, and a compact
  `statusline(bufnr?)` component.
- Add Source-aware target handling for external URLs, relative and absolute
  files, `file:line`, anchors, file anchors, wiki links, images, and multiple
  targets. File targets open inside Neovim; external targets use `vim.ui.open`.
- Add configurable Reader and Float mappings, explicit Reader passthrough
  policies, and stable `<Plug>(MarkdownTableWrap...)` actions without adding
  invasive default Source mappings.
- Add `:MarkdownTableOpen`, split/vsplit/tab variants,
  `:MarkdownTableInspect`, and `:MarkdownTableHelp`; keep
  `:MarkdownTableOpenLink` as a compatibility alias.
- Add `MarkdownTableWrapReaderEnter`, `MarkdownTableWrapReaderLeave`,
  `MarkdownTableWrapViewChanged`, and `MarkdownTableWrapRendered` `User`
  events with safe Source/view identifiers.
- Add LuaLS types for configuration, contexts, targets, actions, mappings, and
  resolver callbacks.

### Changed

- Treat Reader, Inline, Float, and Source as views of one canonical Source for
  actions and navigation. Relative links now resolve from the Source file in
  every plugin-owned view.
- Keep multiple Reader windows for one Source isolated by window width and
  cursor while sharing Source lifetime safely; Source edits refresh dependent
  Readers without replacing a visible Source window.
- Expand `:checkhealth markdown-table-wrap` with active context, resolver,
  mapping, theme, module, and renderer-coexistence diagnostics.

### Fixed

- Preserve Reader `gx` behavior outside rendered targets by invoking the
  captured Source mapping or native fallback exactly once, including callback,
  string, expression, remap, and `replace_keycodes` cases.
- Make implicit Reader exits through `:bnext`, `:bprevious`, `<C-^>`, window
  changes, and buffer deletion restore Source ownership and window options
  without losing unsaved changes or exposing the scratch Reader in buffer
  lists.
- Preserve alternate-buffer navigation and add explicit next/previous/select,
  split, vertical-split, and tab actions that leave disposable views safely.
- Wrap inline-code spans at display-width-safe character boundaries when the
  code token itself is wider than its allocated cell. Code that fits remains a
  single styled span, while narrow Reader and Inline tables keep every border
  aligned.
- Re-check the remaining cell tail after a preferred soft-wrap boundary so
  wide CJK punctuation cannot leave one rendered row wider than its table.

## 0.2.3 - Inline Rendering Corrections

### Fixed

- Keep linked semantic table highlights background-transparent so Inline replace
  mode does not render black or colorscheme-filled rectangles inside cells.
  Explicit `bg` values remain supported for intentional cell or token fills.
- Remove paired inline-code delimiters from link and image labels before width
  calculation so concealed backticks cannot shift Inline table separators.

## 0.2.2 - Stability And Editor Coexistence

### Added

- Add `reader.auto_open = "has_table" | "always"`. The default enters Reader
  automatically only when a supported buffer contains a table; `"always"`
  preserves the previous all-document Reader behavior.
- Add `rmd` to the built-in filetypes so standard Neovim R Markdown detection
  works without `extra_filetypes`.
- Add `get_buffer_config(bufnr)` and `get_preview_mode(bufnr)` for inspecting
  effective per-buffer view configuration.
- Reapply semantic table highlights after `ColorScheme` events.
- Add regression coverage for large invalid pipe candidates, buffer-local
  scheduling/modes, mapping preservation, lifecycle cleanup, and compact border
  highlight spans.

### Changed

- Default `map_gx` to `false`, leaving existing Source-buffer `gx` mappings
  untouched. Table-aware link opening remains available in Reader, through
  `:MarkdownTableOpenLink`, or by explicitly setting `map_gx = true`.
- Keep runtime view, auto-preview, inline viewport, and deferred refresh state
  per buffer instead of mutating global setup values.
- Scan buffer lines and fenced blocks in one parsing pass, avoiding the previous
  quadratic worst case on long runs of pipe-like text.
- Accept top-level tables indented by up to three spaces, normalize body rows
  with missing cells (including eligible rows without a literal pipe), and stop
  before blockquote/list/other Markdown block starts.
- Track arbitrary-length backtick runs while splitting table rows so matching
  code spans can safely contain pipes.
- Merge continuous border highlights into ranges instead of creating an extmark
  for every border character.
- Automatically keep table-free Markdown in Source under the new default Reader
  policy.

### Fixed

- Preserve, invoke, and restore existing callback, string, and expression `gx`
  mappings outside table cells when the table-aware mapping is explicitly
  enabled.
- Prevent delayed refresh work in one buffer from being cancelled by or applied
  to another buffer.
- Restore Inline window-local wrap and conceal options when leaving or clearing
  a rendered buffer, and dispose retained buffer state on wipeout.
- Keep all wrapped header rows on the Header highlight path in Inline replace
  and insert modes.
- Dispose stale Inline viewport offsets during repeated `setup()` calls.
- Cancel delayed refreshes belonging to a previous `setup()` instance and
  reconfigure open Reader windows with the new Reader options while closing
  stale Float previews.
- Apply `:MarkdownTableDisableAutoPreview` from Reader to its backing source
  buffer instead of the protected Reader scratch buffer.
- Validate nested Reader options before applying them to a window.
- Preserve custom theme presets supplied through setup instead of replacing them
  during validation.
- Let direct custom highlight specs replace a preset's linked base highlight,
  and replay those overrides correctly after a colorscheme change.

## 0.2.1 - Reader Workflow And Regression Coverage

### Added

- Add coverage for Reader refresh and save forwarding, configuration validation,
  navigation, fitting behavior, wrapping metadata, and lazy-loading timing.
- Test the supported Neovim 0.10 baseline and stable Neovim in GitHub Actions.
- Add `tests/README.md` with the automated coverage map and release-only manual
  checks for terminal, compositor, and extmark interactions.
- Add `:MarkdownTableToggleInline` for switching from Reader or Source to an
  editable inline rendering layer.

### Fixed

- Ignore table-shaped text inside backtick- and tilde-fenced code blocks.
- Keep cell navigation correct when double-backtick inline code contains pipes.
- Install the table-aware `gx` mapping when a supported buffer existed before
  plugin setup, including filetype-based lazy-loading flows.
- Validate malformed nested configuration values before they reach rendering.

## 0.2.0 - Full-Document Reader

### Added

- Add a full-document reader mode with `preview_mode = "reader"`.
- Replace pipe tables with real Unicode buffer lines in reader mode while leaving the source Markdown buffer unchanged.
- Add `:MarkdownTableReader`, `:MarkdownTableToggleReader`, and `:MarkdownTableEditSource`.
- Preserve native wrapping for non-table Markdown in reader mode.
- Support direct source editing, Visual selection, and rendered-link `gx` navigation from the reader.
- Add `fit_to_window = true` so many-column tables may shrink below the preferred column width when required to fit the text area.

### Changed

- Make Reader the default preview mode so every table is rendered without cursor focus.
- Keep Visual selection inside Reader so copying uses real rendered lines and remains in Reader after yank.

### Fixed

- Avoid raw source pipes leaking from soft-wrapped Markdown table rows by using real rendered lines in reader mode.
- Account for the window text offset, including number, sign, and fold columns, when calculating rendered table width.

### Notes

- Inline mode remains available for source-position-preserving overlays. Reader mode is recommended when native prose wrapping and stable always-visible tables are both required.

## 0.1.5 - Cursor-Scoped Inline Wrapping

### Added

- Add cursor-scoped inline wrapping through `inline_wrap_scope = "cursor"`.
- Restore ordinary Markdown paragraph wrapping when the cursor leaves an inline table.

### Fixed

- Avoid disabling `wrap` for the entire Markdown window when inline tables are rendered with the default cursor-scoped policy.

## 0.1.4 - Floating Link Navigation

### Fixed

- Add buffer-local `gx` support inside floating table previews.
- Open the original URL instead of the rendered link label.
- Preserve link URL metadata through wrapping and rendering.
- Support links spanning multiple rendered lines.
- Prevent native `gx` from opening labels such as `youtube` or `Details`.

## 0.1.3 - Inline Selection And Extra-Line Highlights

### Added

- Add `clear_on_visual` so Inline reveals source Markdown during Visual,
  Visual-Line, and Visual-Block selection, then renders again after selection.

### Fixed

- Use the correct rendered-row index when styling extra Inline virtual lines.

## 0.1.2 - Setup And Defaults Cleanup

### Fixed

- Avoid overriding user configuration when `setup()` is called manually before `plugin/markdown-table-wrap.lua` is sourced, which affects package managers such as `vim.pack`.

### Changed

- `inline_viewport_scrolling` now defaults to `false` so the full rendered table is visible inline on first use.
- `highlight_preset` now defaults to `default`, which links into standard Neovim highlight groups and fits arbitrary colorschemes more naturally.
- Documentation now explains inline viewport behavior near the top of the help text instead of only through commands and options.

## 0.1.1 - Inline Rendering Compatibility Fixes

### Changed

- Default inline replace rendering now uses `inline_virtual_text = "overlay"` for a more portable extmark rendering path.
- Inline replace mode now temporarily disables window-local `wrap` by default through `inline_disable_wrap = true`.

### Fixed

- Prevent source Markdown fragments from leaking below inline rendered tables when long concealed rows soft-wrap on some Linux terminal setups.
- Keep inline table rendering behavior aligned more closely between macOS and Linux in viewport mode.

## 0.1.0 - Initial Public Release

### Added

- Inline replacement renderer for Markdown pipe tables.
- Floating table preview fallback.
- Automatic whole-buffer table rendering in Markdown buffers.
- Source reveal in Insert mode and rendered table view in Normal mode.
- Inline viewport scrolling for rendered tables taller than the source table.
- Toggle command for switching between viewport-sliced and full inline rendering.
- Floating preview can be used for long-table reading without clearing inline rendering.
- Cell wrapping with CJK/English display width support through `vim.api.nvim_strwidth`.
- Escaped pipe support and inline-code-aware pipe splitting.
- Single-backtick and double-backtick inline code spans.
- Inline Markdown display for code, bold, italic, strikethrough, links, and `<br>` hard breaks.
- Inline highlight syntax with `==text==`.
- Link icon configuration for wiki links, images, and custom URL patterns such as GitHub, YouTube, and Bilibili.
- Tokyo Night, Catppuccin, default, render-markdown-inspired, and auto highlight presets.
- Inline custom themes and theme-directory loading.
- Source-aware table cell navigation commands.
- Viewport top/bottom jump commands for long inline tables.
- Headless Neovim regression suite and GitHub Actions CI.
- `:checkhealth markdown-table-wrap`.
- LazyVim/lazy.nvim installation documentation.

### Known Limitations

- Inline replacement uses virtual text and optional virtual lines, which are visual rows rather than real buffer lines.
- Treesitter-aware table discovery is not implemented yet.
- This release is table-focused and intentionally does not replace general Markdown rendering.
