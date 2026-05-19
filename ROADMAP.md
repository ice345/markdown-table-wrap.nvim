# markdown-table-wrap.nvim Roadmap

Goal: become a production-quality Neovim Markdown pipe table renderer that can replace `render-markdown.nvim`'s table rendering,
while coexisting cleanly with `render-markdown.nvim` for non-table Markdown features.

This roadmap intentionally treats "full render-markdown replacement" as a later product decision.
The first publishable target is narrower and more realistic: best-in-class pipe table rendering.

## Phase 0: Stabilize The Current MVP

Target: make the current local plugin predictable enough for daily use.

Deliverables:

- Keep `render-markdown.nvim` table rendering disabled via documented config.
- Render all tables in a Markdown buffer automatically.
- Keep source hidden in Normal mode and visible in Insert mode.
- Support floating preview and inline replace preview.
- Preserve window-local `conceallevel` and `concealcursor`.
- Remove source leakage at the right edge with controlled overlay fill.
- Keep the existing LazyVim local plugin spec working.

Exit criteria:

- Opening a Markdown file renders all pipe tables without manual commands.
- Insert mode reliably exposes source text.
- Normal mode does not leak raw table source.
- No visible conflict with `render-markdown.nvim` table rendering disabled.

## Phase 1: Correct Table Parsing

Target: parse GitHub Flavored Markdown pipe tables correctly enough for real documents.

Deliverables:

- Escaped pipes: `\|`.
- Pipes inside inline code spans.
- Leading and trailing pipe optionality.
- Alignment parsing: `:---`, `---:`, `:---:`.
- Empty cells and missing trailing cells.
- `<br>` / `<br/>` hard breaks inside cells.
- Mixed Chinese, Japanese, English, emoji, and Nerd Font width handling.
- Fuzz tests for malformed table-like lines.

Exit criteria:

- Parser test suite covers normal, malformed, and mixed-width tables.
- Parser does not falsely consume adjacent non-table paragraphs.

## Phase 2: Inline Markdown Token Rendering

Target: render common inline Markdown inside table cells with stable styling.

Required token styles:

- Inline code: green code style.
- Bold: Tokyo Night gold.
- Italic: Tokyo Night blue.
- Strikethrough: red strikethrough.
- Links: cyan underline, URL hidden.
- Hard break: real cell-internal line break.

Stretch tokens:

- Images as alt text or configurable icon + alt text.
- Wiki links.
- Inline highlight: `==text==`.
- HTML entities.

Exit criteria:

- Inline preview and floating preview render the same token styles.
- Token spans survive wrapping, padding, and column alignment.
- Markdown markers do not affect column width.

## Phase 3: Wrapping And Layout Engine

Target: make table layout visually stable and configurable.

Deliverables:

- Stable column width distribution.
- Configurable min/max column width.
- Configurable max table width ratio.
- Row separators.
- Header separators.
- Optional compact mode.
- Optional no-row-separator mode.
- Correct padding with double-width characters.
- Alignment support per column.
- Avoid layout shifts on cursor movement.

Exit criteria:

- Large tables remain readable in normal terminal widths.
- Visual output is deterministic for a given window width and config.

## Phase 4: Display Engine And UX

Target: make inline rendering feel native despite Neovim virtual-line limitations.

Deliverables:

- Whole-buffer table rendering.
- Debounced refresh on text/window changes.
- Cache by buffer changedtick, window width, and render config.
- Multi-window support.
- Source reveal in Insert mode.
- Source hiding in Normal mode.
- Reliable refresh command.
- Reliable table-view scroll commands.
- Optional source fold mode for very large tables.
- Optional current-table-only mode for performance.

Exit criteria:

- No raw source leaks in Normal mode.
- Rendering remains stable while moving the cursor.
- User has a documented way to browse long rendered tables.

Known limitation:

- `virt_lines` are not real buffer lines. The cursor cannot land on them. Long rendered rows need scroll-based viewing or a future fold/display strategy.

## Phase 5: Theme And Highlight System

Target: make the plugin visually consistent across common themes.

Deliverables:

- Default Tokyo Night friendly palette.
- Configurable highlight groups:
  - `MarkdownTableWrapBorder`
  - `MarkdownTableWrapHeader`
  - `MarkdownTableWrapInline`
  - `MarkdownTableWrapCode`
  - `MarkdownTableWrapBold`
  - `MarkdownTableWrapItalic`
  - `MarkdownTableWrapStrike`
  - `MarkdownTableWrapLink`
  - `MarkdownTableWrapBlank`
- Presets:
  - `tokyonight`
  - `catppuccin`
  - `default`
  - `render_markdown`
- User highlight overrides by semantic key.
- Documented override examples.

Exit criteria:

- Users can match their colorscheme without editing plugin source.
- Floating and inline previews use the same highlight model.

## Phase 6: Test Suite And CI

Target: make the plugin safe to publish and maintain.

Deliverables:

- `stylua.toml`.
- Lua unit tests for parser, wrapping, width, Markdown tokenization.
- Headless Neovim tests for extmark rendering.
- Golden output tests for rendered table strings.
- CI on GitHub Actions:
  - formatting
  - unit tests
  - headless Neovim tests

Current status:

- Headless Neovim runner is split into focused specs under `tests/spec/`.
- Parser, inline Markdown tokenization, wrapping, rendering snapshots, theme presets, inline extmarks, floating highlights, and system render chain are covered.
- The system render-chain test verifies that adjacent pipe-like prose is not concealed and styled Markdown survives into inline replacement output.

Exit criteria:

- Pull requests can be validated without manual UI testing.
- Rendering changes are reviewed through golden diffs.

## Phase 7: LazyVim And Plugin Distribution

Target: publish as a clean LazyVim/lazy.nvim-compatible plugin.

Deliverables:

- Final repository name: `markdown-table-wrap.nvim`.
- MIT license.
- README with:
  - screenshots / GIFs
  - LazyVim install example
  - `render-markdown.nvim` coexistence example
  - configuration reference
  - known limitations
- `:checkhealth markdown-table-wrap`.
- Semantic version tags.
- GitHub release notes.
- Minimal issue templates.

Exit criteria:

- Fresh LazyVim user can install with one spec.
- User can disable `render-markdown.nvim` table rendering by copying one documented config snippet.
- Plugin works without external binaries.

## Phase 8: Advanced Table UX

Target: become better than existing table renderers, not just a workaround.

Possible features:

- Cell navigation.
- Current cell highlight.
- Copy rendered table.
- Open long cell in floating detail view.
- Edit current cell in a focused floating editor.
- Sort rows.
- Align/reformat source table command.
- Export rendered table to plain text.
- Optional table of contents integration for documents with many tables.

Exit criteria:

- Features remain optional and do not compromise the read-only rendering core.

## Phase 9: Evaluate Full Markdown Renderer Scope

Target: decide whether to stay table-focused or compete with `render-markdown.nvim` broadly.

Full replacement would require:

- Headings.
- Code blocks.
- Inline code.
- Links.
- Images.
- Lists.
- Checkboxes.
- Block quotes.
- Callouts.
- HTML.
- LaTeX.
- Tables.
- Theming.
- Conceal behavior.
- Treesitter integration.

Decision rule:

- Do not attempt full replacement until table rendering is stable, tested, documented, and published.
- If full replacement is pursued, split table renderer and general Markdown renderer into separate modules so users can opt into only the table engine.
