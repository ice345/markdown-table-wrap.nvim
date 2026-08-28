# Test Suite

Run the full regression suite from the plugin root:

```sh
nvim --headless -u NONE -i NONE \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

The suite is organized by responsibility instead of the order in which features
were added:

| Area | Specs | Main regression risks covered |
| --- | --- | --- |
| GFM parsing | `parser_spec.lua` | delimiter validation, escaped/optional outer pipes, GFM missing-cell rows, fenced and block boundaries, linear large-document scanning |
| Inline Markdown | `markdown_spec.lua`, `wrap_spec.lua` | code, emphasis, links, icons, concealed code delimiters, hard breaks, CJK width, preferred wrap boundaries, metadata preservation |
| Geometry | `width_spec.lua`, `render_spec.lua` | display width, padding, alignment, border variants, source-row mapping, fit-to-window and intentional overflow |
| Neovim views | `inline_spec.lua`, `reader_spec.lua`, `mode_spec.lua`, `lifecycle_spec.lua`, `multiwindow_spec.lua`, `cell_ops_spec.lua` | conceal/extmarks, wrap scope, viewport scrolling, per-buffer debounce/state, Reader policy, native buffer exits, shared-Source Readers, window option and lifetime cleanup, Source-aware cell yank/change/put and visible Visual feedback |
| Context and actions | `context_spec.lua`, `actions_spec.lua`, `inspect_spec.lua` | Source resolution across modes, stable actions and Plug mappings, disabled/local mappings, passthrough, inspect/help/statusline, health diagnostics |
| Links and mappings | `links_spec.lua`, `mappings_spec.lua` | relative/absolute files, line/anchor/wiki/image/URL targets, Float/Reader metadata, custom resolver, selector, callback/string/expr/remap/replace_keycodes restore semantics |
| Interaction | `nav_spec.lua`, `config_spec.lua`, `system_spec.lua` | cell navigation, commands, lazy-loading timing, configuration validation, filetype boundaries |
| Themes | `theme_spec.lua` | presets, overrides, auto-detection, and theme files |
| v0.4 model/performance | `v04_spec.lua`, `fixtures/gfm_tables.lua`, `benchmark.lua` | exact Source spans, token contract, classified GFM corpus, discovery fallback, cache invalidation/cleanup, reference budgets |

Headless tests prove parser and Neovim API behavior. Keep these manual checks
for each release because terminal font shaping, compositor behavior, and other
plugins' extmarks are outside a headless process:

1. Test Reader and inline mode in a narrow terminal with CJK text, long URLs,
   inline-code tokens wider than their cells, and a table wider than the
   window; every rendered border should stay aligned.
2. Test with native `wrap` enabled for normal Markdown prose.
3. Test with `render-markdown.nvim` loaded and its pipe-table renderer disabled.
4. Test code-wrapped link/image labels such as ``[`overview`](path.md)`` and
   confirm Inline separators stay aligned.
5. In Reader, test `yic` on a wrapped link/code cell and confirm the register
   contains raw Markdown; test `vic`, native `v`/`V`/`<C-v>`, `dic`, `cic`,
   `cip`, and `c` on both a cell and ordinary prose. Confirm `c` delegates to
   the user's Source mapping outside cells.
6. Test `gx`, `:w`, `:wq`, `:x`, and `ZZ` from Reader against a real file.
7. Test native `:bnext`, `:bprevious`, and `<C-^>`, plus configured custom
   `H`/`L`, Bufferline, Telescope, and Harpoon transitions with a modified
   Source buffer.
8. Test Source-relative file, anchor, split, and tab opening from Reader and
   Float, including a missing target that must preserve the current view.
9. Test at least one Linux terminal/compositor and one macOS terminal when
   changing overlay, conceal, or wrap behavior.
10. Switch away from an automatically opened Reader with native buffer
   navigation, return to its Source, and verify Reader reopens; explicit close
   or edit must remain paused.
11. Run `tests/benchmark.lua` and compare its scenarios with
    `docs/performance.md` on the same machine used for the release check.
12. For large Reader or extmark changes, rerun the benchmark with
    `MARKDOWN_TABLE_WRAP_BENCH_READER=1`; then repeat `gg`, `G`, search,
    selection, and yank in a real UI because headless cursor timing excludes
    terminal redraw.
