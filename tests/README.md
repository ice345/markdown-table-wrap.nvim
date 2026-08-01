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
| Neovim views | `inline_spec.lua`, `reader_spec.lua`, `mode_spec.lua`, `lifecycle_spec.lua` | conceal/extmarks, wrap scope, viewport scrolling, per-buffer debounce/state, window option restoration, Reader policy, buffer cleanup, view toggles |
| Interaction | `nav_spec.lua`, `config_spec.lua`, `system_spec.lua` | cell navigation, commands, lazy-loading timing, configuration validation, filetype boundaries |
| Themes | `theme_spec.lua` | presets, overrides, auto-detection, and theme files |

Headless tests prove parser and Neovim API behavior. Keep these manual checks
for each release because terminal font shaping, compositor behavior, and other
plugins' extmarks are outside a headless process:

1. Test Reader and inline mode in a narrow terminal with CJK text, long URLs,
   inline code, and a table wider than the window.
2. Test with native `wrap` enabled for normal Markdown prose.
3. Test with `render-markdown.nvim` loaded and its pipe-table renderer disabled.
4. Test code-wrapped link/image labels such as ``[`overview`](path.md)`` and
   confirm Inline separators stay aligned.
5. Test `gx`, `:w`, `:wq`, `:x`, and `ZZ` from Reader against a real file.
6. Test at least one Linux terminal/compositor and one macOS terminal when
   changing overlay, conceal, or wrap behavior.
