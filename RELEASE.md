# Release Checklist

Target version: `v0.1.2`

Use this before tagging a public release.

## Required

- [x] Run headless tests from repository root:

  ```sh
  nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
    -c "set rtp+=." \
    -c "luafile tests/run.lua" \
    -c "qa!"
  ```

- [ ] Run `:checkhealth markdown-table-wrap` in a real Neovim session.
- [ ] Verify LazyVim install snippet from README.
- [ ] Verify coexistence with `render-markdown.nvim` and `pipe_table.enabled = false`.
- [ ] Verify inline rendering in Normal mode.
- [ ] Verify inline viewport scrolling with `:MarkdownTableScrollDown` and `:MarkdownTableScrollUp`.
- [ ] Verify inline viewport/full toggle with `:MarkdownTableToggleInlineViewport`.
- [ ] Verify viewport top/bottom jumps with `:MarkdownTableScrollTop` and `:MarkdownTableScrollBottom`.
- [ ] Verify link icons and `==highlight==` rendering.
- [ ] Verify `gx` / `:MarkdownTableOpenLink` opens the source table cell URL.
- [ ] Verify source reveal in Insert mode.
- [ ] Verify floating preview.
- [ ] Verify a wide mixed Chinese/English table.
- [ ] Verify GFM parser boundaries:
  - [ ] escaped pipe
  - [ ] pipe inside inline code
  - [ ] double-backtick code span
  - [ ] invalid delimiter row rejection
  - [ ] adjacent pipe-like prose is not concealed
- [ ] Verify inline token styles:
  - [ ] code
  - [ ] bold
  - [ ] italic
  - [ ] strikethrough
  - [ ] link

## Documentation

- [x] README has screenshots or GIFs.
- [x] README documents known virtual-line limitations.
- [x] README documents configuration options.
- [x] README documents highlight groups.
- [x] Vim help document is present.
- [x] CHANGELOG is present.
- [x] CONTRIBUTING guide is present.
- [x] PUBLISHING guide is present.
- [x] GitHub issue templates are present.
- [x] GitHub pull request template is present.
- [x] ROADMAP is current.

## Tagging

- [x] Update version notes.
- [ ] Create semantic version tag.
- [ ] Publish GitHub release notes.

## Verified In This Workspace

- [x] Headless test suite: `PASS 32 tests`.
- [x] Help tags generated for `doc/markdown-table-wrap.txt`.
- [x] `:help markdown-table-wrap` opens in headless Neovim.
- [x] `:checkhealth markdown-table-wrap` completes in headless Neovim.
- [x] Inline viewport scrolling is covered by regression tests.
- [x] Inline viewport/full toggle is covered by regression tests.
- [x] Viewport top/bottom jumps are covered by regression tests.
- [x] Link icons and `==highlight==` rendering are covered by regression tests.
- [x] Floating preview preserving inline rendering is covered by regression tests.

## Screenshots To Capture Before Publishing

- `01-inline-tokyonight.png`: Normal mode inline rendering of a wide table in Tokyo Night.
- `02-inline-scroll-before-after.gif`: Press `<leader>mj` / `<leader>mk` or run `:MarkdownTableScrollDown` / `:MarkdownTableScrollUp` to show inline viewport scrolling.
- `02b-inline-full-toggle.png`: Press `<leader>mq` or run `:MarkdownTableToggleInlineViewport` to show full inline expansion.
- `02c-link-icons-highlight.png`: A table containing `[YouTube](https://youtube.com)`, `[[Wiki]]`, `![alt](image.png)`, and `==highlight==`.
- `03-floating-long-table.png`: Floating preview of the same long table, showing that all wrapped rows are readable in a real preview buffer.
- `04-insert-source-reveal.png`: Insert mode showing the original Markdown source table.
- `05-render-markdown-coexistence.png`: A Markdown document where headings/lists/code are rendered by `render-markdown.nvim`, while the table is rendered by this plugin.

## Release Notes Draft

### markdown-table-wrap.nvim v0.1.1

Inline rendering compatibility release focused on stabilizing replace-mode rendering across macOS and Linux terminal setups.

Highlights:

- Default replace-mode rendering now uses Neovim's `overlay` virtual text path.
- Inline replace mode temporarily disables window-local `wrap` so concealed long Markdown rows do not leak through below the rendered table.
- Cross-platform behavior is more consistent for inline viewport rendering of long tables.

Known limitations:

- Extra wrapped rows still use `virt_lines`, so they are visual rows rather than real cursor-addressable buffer lines.
- The plugin remains table-focused and does not replace general Markdown rendering.

### markdown-table-wrap.nvim v0.1.0

Initial public release of a Neovim 0.10+ Markdown pipe table renderer focused on wrapped cell content.

Highlights:

- Inline replacement rendering with extmark conceal, overlay virtual text, and virtual lines.
- Floating preview fallback.
- Automatic whole-buffer rendering for Markdown buffers.
- CJK/English display-width-aware wrapping and padding.
- GFM-style parser coverage for escaped pipes, pipes inside inline code, optional outer pipes, alignments, missing cells, and invalid delimiter rejection.
- Inline cell rendering for code, bold, italic, strikethrough, links, and hard breaks.
- Tokyo Night, Catppuccin, default, render-markdown-inspired, and auto theme presets.
- LazyVim/lazy.nvim installation docs, healthcheck, Vim help, CI, and regression tests.

Known limitations:

- Extra wrapped rows use `virt_lines`, so they are visual rows rather than real cursor-addressable buffer lines.
- The plugin is table-focused and does not replace general Markdown rendering.
