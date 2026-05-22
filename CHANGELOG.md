# Changelog

All notable changes to `markdown-table-wrap.nvim` are documented here.

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
