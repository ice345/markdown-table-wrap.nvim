# Publishing Guide

This guide explains how to publish `markdown-table-wrap.nvim` so other users can install it with lazy.nvim or LazyVim.

## 1. Create The GitHub Repository

Create a public GitHub repository named:

```text
markdown-table-wrap.nvim
```

Then initialize and push from the plugin directory:

```sh
cd markdown-table-wrap.nvim
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin git@github.com:ice345/markdown-table-wrap.nvim.git
git push -u origin main
```

Use HTTPS instead of SSH if preferred:

```sh
git remote add origin https://github.com/ice345/markdown-table-wrap.nvim.git
```

## 2. Verify CI

After pushing, open the GitHub Actions tab and make sure CI passes.

The workflow checks:

- Lua formatting with StyLua.
- Headless Neovim regression tests.

## 3. Tag The First Release

For the initial public release:

```sh
git tag -a v0.1.0 -m "markdown-table-wrap.nvim v0.1.0"
git push origin v0.1.0
```

## 4. Create A GitHub Release

Open GitHub:

```text
Repository -> Releases -> Draft a new release
```

Use:

```text
Tag: v0.1.0
Title: markdown-table-wrap.nvim v0.1.0
```

Paste the release notes draft from the end of this file.

Recommended release assets/screenshots:

- `01-inline-tokyonight.png`: Normal mode inline rendering of a wide table.
- `02-inline-scroll-before-after.gif`: Inline viewport scrolling with `:MarkdownTableScrollDown` / `:MarkdownTableScrollUp`.
- `02b-inline-full-toggle.png`: Full inline expansion after `:MarkdownTableToggleInlineViewport`.
- `02c-link-icons-highlight.png`: Link icons, wiki/image icons, and `==highlight==`.
- `03-floating-long-table.png`: Floating preview of a long wrapped table.
- `04-insert-source-reveal.png`: Insert mode source reveal.
- `05-render-markdown-coexistence.png`: render-markdown.nvim handling non-table Markdown while this plugin handles the table.

## 5. User Installation

LazyVim / lazy.nvim users can install from GitHub:

```lua
return {
  {
    "ice345/markdown-table-wrap.nvim",
    ft = "markdown",
    opts = {
      highlight_preset = "auto",
    },
  },
}
```

If they also use `render-markdown.nvim`, they should disable its table renderer:

```lua
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    pipe_table = {
      enabled = false,
    },
  },
}
```

## 6. Updating The Plugin

Users update it through their plugin manager:

```vim
:Lazy update markdown-table-wrap.nvim
```

For future releases:

```sh
git tag -a v0.2.1 -m "markdown-table-wrap.nvim v0.2.1"
git push origin v0.2.1
```

Then draft a new GitHub release from that tag.

## 7. Release Checklist

Use this before tagging a public release.

- Run the headless test suite from the repository root.
- Run `:checkhealth markdown-table-wrap` in a real Neovim session.
- Verify the README install snippet with your current plugin manager setup.
- Verify coexistence with `render-markdown.nvim` and `pipe_table.enabled = false`.
- Verify inline rendering in Normal mode.
- Verify the default full-document Reader opens automatically without cursor focus.
- Verify Reader prevents direct text edits while Visual selection and yank stay inside Reader.
- Verify `i`, `a`, `o`, and related Insert commands return to the mapped source line.
- Verify Reader reopens after `InsertLeave` and after leaving Visual mode.
- Verify `:MarkdownTableToggleReader` and `:MarkdownTableEditSource` state transitions.
- Verify `:MarkdownTableToggleInline` switches Reader/Source into Inline and back to Source.
- Verify `:w`, `:wq`, `:x`, and `ZZ` from Reader save the backing Markdown file.
- Verify inline viewport scrolling with `:MarkdownTableScrollDown` and `:MarkdownTableScrollUp`.
- Verify inline viewport/full toggle with `:MarkdownTableToggleInlineViewport`.
- Verify viewport top/bottom jumps with `:MarkdownTableScrollTop` and `:MarkdownTableScrollBottom`.
- Verify link icons and `==highlight==` rendering.
- Verify `gx` / `:MarkdownTableOpenLink` opens the source table cell URL.
- Verify source reveal in Insert mode.
- Verify floating preview.
- Verify a wide mixed Chinese/English table.
- Verify parser boundaries: escaped pipe, pipe inside inline code, double-backtick code span, invalid delimiter row rejection, and adjacent pipe-like prose not being concealed.
- Verify inline token styles: code, bold, italic, strikethrough, and link.

## 8. Release Notes Draft

### markdown-table-wrap.nvim v0.2.1

This release makes the Reader workflow more natural for daily Markdown writing
and strengthens the release regression suite.

Highlights:

- Reader now forwards `:w`, `:wq`, `:x`, and `ZZ` to the backing Markdown
  buffer, so saving does not require manually returning to Source.
- Adds `:MarkdownTableToggleInline` for switching from Reader or Source into
  an editable inline table view.
- Avoids rendering table-shaped examples inside fenced code blocks.
- Fixes cell navigation for double-backtick inline code containing pipes.
- Makes table-aware `gx` available when LazyVim loads the plugin after a
  Markdown buffer's FileType event.
- Validates malformed nested configuration values before rendering.
- Expands the test suite and CI coverage to Neovim v0.10.4 and stable.

Known limitations:

- Inline mode remains dependent on terminal/compositor/extmark behavior. Use
  Reader for the most stable view when native prose wrapping is enabled.
- The plugin focuses on pipe tables; it does not replace general Markdown
  rendering provided by render-markdown.nvim.

### markdown-table-wrap.nvim v0.2.0

This release introduces a stable full-document Reader for Markdown tables.

Highlights:

- Adds `preview_mode = "reader"`, which renders every Markdown table without requiring cursor focus.
- Uses real Unicode buffer lines for rendered tables, avoiding raw pipe leakage when ordinary Markdown `wrap` is enabled.
- Keeps the Markdown source buffer untouched and read-only only in Reader mode.
- Allows Visual selection and yank directly from rendered table lines while keeping Reader active.
- Returns to the mapped source line for `i`, `a`, `I`, `A`, `o`, and `O`, then reopens Reader after editing.
- Adds `:MarkdownTableReader`, `:MarkdownTableToggleReader`, and `:MarkdownTableEditSource`.
- Adds `fit_to_window = true` and accounts for the window text offset when allocating columns.
- Preserves inline and floating modes for users who prefer source-position-preserving overlays or focused previews.
- Adds Reader lifecycle, width, link, and unsaved-buffer regression tests.

Known limitations:

- Inline mode still uses virtual text and virtual lines, so Reader mode is recommended when native prose wrapping and stable table rendering are both required.
- The plugin remains focused on Markdown pipe tables and does not replace general Markdown rendering.
