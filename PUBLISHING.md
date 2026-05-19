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

Paste the release notes from `RELEASE.md`.

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
git tag -a v0.1.1 -m "markdown-table-wrap.nvim v0.1.1"
git push origin v0.1.1
```

Then draft a new GitHub release from that tag.
