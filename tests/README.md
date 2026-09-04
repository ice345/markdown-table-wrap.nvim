# Test Suite

Run the full regression suite from the plugin root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

The suite is organized by responsibility instead of the order in which features
were added:

| Area | Specs | Main regression risks covered |
| --- | --- | --- |
| GFM parsing | `parser_spec.lua` | delimiter validation, escaped/optional outer pipes, GFM missing-cell rows, shared UTF-8/pipe/fence semantics, blockquote Source spans, fenced and block boundaries, linear large-document scanning |
| Inline Markdown | `markdown_spec.lua`, `wrap_spec.lua` | code, emphasis, links, icons, concealed code delimiters, hard breaks, CJK width and sentence punctuation, preferred wrap boundaries, metadata preservation |
| Geometry | `width_spec.lua`, `render_spec.lua` | display width, padding, alignment, border variants, source-row mapping, fit-to-window, intentional width overflow, and visible excess-Source-cell diagnostics |
| Neovim views | `inline_spec.lua`, `reader_spec.lua`, `mode_spec.lua`, `lifecycle_spec.lua`, `multiwindow_spec.lua`, `cell_ops_spec.lua`, `reader_ergonomics_spec.lua`, `table_edit_spec.lua` | conceal/extmarks, wrap scope, viewport scrolling, per-buffer debounce/state and setup preservation/reset, Reader policy, auxiliary-buffer exclusion, native buffer exits, shared-Source Readers, multiwindow resize fanout, transactional Reader open/refresh rollback, window option and lifetime cleanup, Source-aware cell registers/count rejection/native `c` motions/undo-redo repeat and visible Visual feedback, sticky headers, indexed cell lookup/refocus, narrow Reader snapshots, help ergonomics, raw-Source formatting, explicit Source table rewrites, adaptive one-cell popup edits, header-row refusal, and unsafe-table guards |
| Context and actions | `context_spec.lua`, `actions_spec.lua`, `inspect_spec.lua` | Source resolution across modes, stable actions and Plug mappings, disabled/local mappings, passthrough, logical statusline rows, excess-cell reporting, Reader key help, and health diagnostics |
| Links, registers, and mappings | `links_spec.lua`, `export_spec.lua`, `mappings_spec.lua` | relative/absolute files, local/remote file URIs, line/anchor/wiki/image/URL targets, external-scheme allowlisting, clipboard-option semantics, Float/Reader metadata, custom resolver, selector, callback/string/expr/remap/replace_keycodes restore semantics |
| Interaction | `nav_spec.lua`, `config_spec.lua`, `system_spec.lua` | logical Source/Reader/Float cell navigation, public Reader→Float→Reader→Inline command transitions, typed leader mapping survival across automatic Reader debounce, Float origin restoration across close/toggle/refresh, Source-resolved status/auto-preview/Inline-viewport commands, viewport-mode feedback, extracted command registration, isolated defaults/options, configuration validation, unknown-option diagnostics, lazy-loading timing, and filetype boundaries |
| Themes | `theme_spec.lua` | presets, overrides, auto-detection, and theme files |
| v0.4 model/performance | `v04_spec.lua`, `fixtures/gfm_tables.lua`, `benchmark.lua` | exact Source spans, token contract, classified GFM corpus, discovery fallback, cache invalidation/cleanup, reference budgets |

Headless tests prove parser and Neovim API behavior. Keep these manual checks
for each release because terminal font shaping, compositor behavior, and other
plugins' extmarks are outside a headless process:

1. Test Reader and inline mode in a narrow terminal with CJK text, long URLs,
   inline-code tokens wider than their cells, and a table wider than the
   window; every rendered border should stay aligned, and `。！？：` should be
   preferred as natural Chinese wrap boundaries.
2. Test with native `wrap` enabled for normal Markdown prose.
3. Test with `render-markdown.nvim` loaded and its pipe-table renderer disabled.
4. Test code-wrapped link/image labels such as ``[`overview`](path.md)`` and
   confirm Inline separators stay aligned.
5. In Reader, test real typed `yic` and `vic` followed by `y` on a wrapped
   link/code cell and confirm both use the exact raw Markdown Source. Repeat
   with named and black-hole registers. Test `vic` followed by `d`, `c`, and
   `p`; `dic`, `cic`, native Source `c` motions, and `.`; one `u` must restore
   a complete `cic` replacement, redo must reapply it, and `.` must then work
   on another logical cell. Confirm counts greater than one are rejected
   unchanged, native `cip` remains reachable from prose and table cells, and
   opt-in cell put works through `:MarkdownTablePutCell` or a configured key. Native
   `v`/`V`/`<C-v>` must continue selecting rendered text. Use CJK/link icons
   and confirm `c` delegates to the user's Source mapping from any Reader
   position. Mistype `yj`, `yk`, `yap`, `dj`, `dk`, and `dd`; each must cancel
   without moving the cursor, changing registers/Source, copying a border, or
   raising `E21`.
6. Test `gx`, `:w`, `:wq`, `:x`, and `ZZ` from Reader against a real file.
7. Test `:MarkdownTableYankCell`, `:MarkdownTableYankTable`, and
   `:MarkdownTableExport[!] [tsv|csv]` in Source, Inline, and Reader. Confirm
   rendered copy omits Markdown syntax/icons, table copy keeps borders, and
   delimiters/quotes/tabs remain one export field. Confirm a table with excess
   cells shows its rendered warning and is refused without changing the current
   register. Repeat once with empty and `unnamedplus` `'clipboard'` settings.
8. Enable `reader.sticky_header` in a real UI, scroll between prose and two
   tables, and confirm the winbar follows the active table and restores the
   user's original winbar on exit.
9. Test native `:bnext`, `:bprevious`, and `<C-^>`, plus configured custom
   `H`/`L`, Bufferline, Telescope, and Harpoon transitions with a modified
   Source buffer. Returning to an unpaused Source must restore the same Reader
   cursor/wrapped-row offset and viewport; moving or scrolling Source before
   reopen must win over the saved Reader view. Inline must retain its per-window
   native cursor and viewport too.
10. Test Source-relative file, anchor, split, and tab opening from Reader and
    Float, including local `file:` URIs, a refused remote-host `file:` URI, an
    untrusted custom scheme, and a missing target that must preserve the
    current view.
11. Starting from an automatically opened Reader, press the configured
    `<leader>mf` Float mapping and wait beyond `debounce_ms`. Confirm the Float
    remains open, then press `q` and confirm Reader returns at the same logical
    cell. Repeat Source→Float→`q` and Inline→Float→`q`, refresh one Float before
    closing it, and exercise status plus auto-preview toggle from Reader and
    Float. No command may store policy against a scratch buffer or emit a false
    filetype warning.
12. Test at least one Linux terminal/compositor and one macOS terminal when
   changing overlay, conceal, or wrap behavior.
13. Switch away from an automatically opened Reader with native buffer
   navigation, return to its Source, and verify Reader reopens; explicit close
   or edit must remain paused.
14. Run `tests/benchmark.lua` and compare its scenarios with
    `docs/performance.md` on the same machine used for the release check.
15. For large Reader or extmark changes, rerun the benchmark with
    `MARKDOWN_TABLE_WRAP_BENCH_READER=1`; then repeat `gg`, `G`, search,
    selection, and yank in a real UI because headless cursor timing excludes
    terminal redraw.
16. Run the Source editing companion commands from Source and Reader: format,
    add/delete/move rows and columns, toggle alignment, and edit a long cell
    in the popup. Confirm each commit is one undo step, Reader/Float returns to
    Source before mutation, header-row delete/move is refused unchanged, and a
    table with excess cells is refused unchanged. Paste a long value and confirm
    the popup grows, soft-wraps, and remains bounded.
17. Open top-level, single-level, and nested blockquote tables with mixed
    spacing before and after `>`. Confirm Reader, Inline, and Float keep the
    quote depth visible; navigation stays inside logical cells; typed `yic`
    excludes `>` and adjacent pipes; `dic`/`cic` change only the exact Source
    cell; and explicit format keeps every generated row inside the quote with
    aligned physical pipes. Confirm a list-contained table remains visible and
    unparsed.
