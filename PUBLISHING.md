# Publishing Guide

This is the maintenance and release procedure for the existing public
repository. The repository has already been created; do not reinitialize it or
rename its development branch as part of a release.

## Repository Facts

- Repository: `ice345/markdown-table-wrap.nvim`
- Remote: `origin` (`git@github.com:ice345/markdown-table-wrap.nvim.git`)
- Development/release branch: `master`
- Latest published tag before this release: `v0.2.2`
- Next planned release: `v0.2.3`
- Supported Neovim baseline: 0.10+

Verify these values rather than assuming the local checkout is current:

```sh
git remote -v
git branch --show-current
git fetch origin --tags
git status --short
git tag --sort=-version:refname | head
```

Release only from `master`, with no unrelated local changes, after the branch is
up to date with `origin/master`.

## 1. Freeze The Release Scope

Before preparing v0.2.3:

1. Stop adding features not listed in the v0.2.3 CHANGELOG section.
2. Review every commit since the previous release:

   ```sh
   git log --oneline v0.2.1..master
   git diff --stat v0.2.1..master
   ```

3. Confirm each user-visible change has a regression test or a documented
   manual check.
4. Confirm the renderer still does not modify Markdown source text.
5. Move unfinished work to [ROADMAP.md](ROADMAP.md); do not describe it as part
   of the release.

## 2. Align Version And Documentation

For v0.2.3, all of the following must agree:

- `M.version` in `lua/markdown-table-wrap/init.lua`
- The top release in `CHANGELOG.md`
- README configuration/default behavior
- `doc/markdown-table-wrap.txt`
- The annotated Git tag `v0.2.3`
- The GitHub release title

Search for stale version/default references:

```sh
rg -n '0\.2\.[0-9]+|map_gx|auto_open|your-name|ft = ' \
  README.md CHANGELOG.md PUBLISHING.md ROADMAP.md doc lua tests
```

Regenerate Vim help tags after help changes:

```sh
nvim --headless -u NONE \
  -c "helptags doc" \
  -c "qa!"
```

Review `doc/tags` and commit it when regeneration changes the file.

## 3. Run Automated Gates

From the plugin repository root:

```sh
stylua --check .
```

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

The GitHub Actions workflow repeats formatting and the headless suite on:

- Neovim 0.10.4
- Neovim stable

Also run whitespace and documentation checks:

```sh
git diff --check
```

```sh
nvim --headless -u NONE \
  -c "set rtp+=." \
  -c "help markdown-table-wrap" \
  -c "qa!"
```

Open every relative link in README, CHANGELOG, PUBLISHING, and ROADMAP during
release review, and confirm every referenced file exists in the checkout.

## 4. Run The v0.2.3 Manual Matrix

Use a saved Markdown file with no table, one short table, one very wide table,
several tables, links, escaped pipes, code spans, and mixed CJK/English text.

### Default Behavior And State Isolation

- With the default `reader.auto_open = "has_table"`, confirm plain Markdown
  remains in Source.
- Confirm a document containing a table automatically opens Reader and renders
  all tables without cursor focus.
- Set `reader.auto_open = "always"` and confirm a table-free supported buffer
  opens Reader.
- Open two Markdown buffers, choose different views, and confirm toggling one
  does not change the other's mode or the global configured default.
- Trigger edits/refreshes in two buffers in quick succession and confirm each
  buffer refreshes itself rather than cancelling or rendering the other.
- Wipe a rendered buffer and confirm reopening a document does not inherit stale
  viewport, timer, or view state.

### Mappings And Links

- Define a custom `gx` mapping before loading the plugin. With default
  `map_gx = false`, confirm the mapping remains unchanged in Source.
- Confirm `:MarkdownTableOpenLink` opens a table-cell URL.
- Set `map_gx = true` and confirm table links open through the opt-in mapping.
- Confirm Reader `gx` opens the original URL rather than its displayed label.
- Confirm ordinary links outside tables retain their normal behavior.

### Reader, Inline, And Float

- Confirm Reader Visual selection/yank uses real rendered lines and does not
  edit source text.
- Confirm `i`, `a`, `I`, `A`, `o`, and `O` return to the mapped source line and
  Reader reopens after `InsertLeave`.
- Confirm `:w`, `:wq`, `:x`, and `ZZ` forward saves to the backing Markdown
  source; confirm anonymous-buffer errors are clear.
- Confirm `:MarkdownTableToggleReader`, `:MarkdownTableEditSource`, and
  `:MarkdownTableToggleInline` have the documented transitions.
- Run `:MarkdownTableDisableAutoPreview` from Reader and confirm it disables
  automatic rendering for the backing Source buffer.
- Confirm Inline restores window-local `wrap`, `conceallevel`, and
  `concealcursor` when leaving the buffer or clearing the view.
- Confirm full Inline and viewport-sliced Inline scrolling/top/bottom commands.
- Confirm linked semantic content highlights do not fill every Inline cell when
  their source group has a background; verify an explicit `bg` still opts in.
- Confirm code-wrapped link and image labels keep Inline separators aligned,
  including labels containing CJK text and multiple backticks.
- Confirm wrapped header continuation rows retain the Header highlight in both
  Inline replace and insert modes.
- Scroll an Inline viewport, call `setup()` again, and confirm the stale viewport
  offset is not retained.
- Change Reader window options through a repeated `setup()` call and confirm an
  already open Reader adopts them; confirm a delayed pre-setup refresh cannot
  overwrite the new configuration.
- Confirm Float opens, scrolls, follows link metadata, and closes with `q`.

### Parsing, Performance, Theme, And Filetypes

- Confirm fenced table-shaped text is ignored, including backtick and tilde
  fences.
- Confirm escaped pipes and pipes inside single/multiple-backtick code spans.
- Confirm invalid delimiter rows and adjacent pipe-like prose are rejected.
- Exercise the large invalid-pipe regression fixture and verify editing remains
  responsive.
- Render a long table and verify border highlighting does not create one extmark
  per border character.
- Switch colorschemes and confirm semantic table highlights are reapplied.
- Confirm lazy-loading and rendering for `markdown`, `quarto`, and `rmd`.
- Confirm coexistence with `render-markdown.nvim` when its
  `pipe_table.enabled` is `false`.
- Run `:checkhealth markdown-table-wrap` in the representative setup.

Record the Neovim version, OS, terminal/UI, colorscheme, and any manual failures
in the release PR or release issue.

## 5. Verify CI On `master`

Push the release-preparation commit normally and wait for every GitHub Actions
matrix job to pass. Do not tag a local commit that is not yet present on
`origin/master`.

Useful checks with GitHub CLI, if installed:

```sh
gh run list --branch master --limit 5
gh run view --log-failed
```

Before tagging:

```sh
git status --short
git rev-parse HEAD
git rev-parse origin/master
```

The final two commit IDs must match and `git status --short` must be empty.

## 6. Tag v0.2.3

Create an annotated tag on the verified `master` commit:

```sh
git tag -a v0.2.3 -m "markdown-table-wrap.nvim v0.2.3"
git show --stat v0.2.3
git push origin v0.2.3
```

Never move or reuse a published tag. If a release contains a defect, prepare a
new patch release such as v0.2.3.

## 7. Publish The GitHub Release

Create a release from the existing tag:

```sh
gh release create v0.2.3 \
  --title "markdown-table-wrap.nvim v0.2.3" \
  --notes-file /path/to/release-notes.md
```

The notes should be derived from the v0.2.2 CHANGELOG entry and should state
the two intentional default changes prominently:

- Reader automatically opens only for supported buffers that contain a table;
  users can set `reader.auto_open = "always"` for the previous behavior.
- Source-buffer `gx` mapping is opt-in with `map_gx = true`; default setup leaves
  existing mappings untouched.

The real media currently tracked in this repository are:

- `docs/01-inline-tokyonight.png`
- `docs/02-inline-scroll.gif`
- `docs/02b-inline-full-toggle.png`
- `docs/03-floating-long-table.png`

Use only those files unless new media is committed and reviewed first. The
plugin itself needs no compiled archive or binary release asset; lazy.nvim
installs directly from the Git tag.

## 8. Verify The Published Tag

After publishing:

1. Open the GitHub release and confirm its tag and target commit.
2. Install from a clean plugin-manager cache using the public specification:

   ```lua
   return {
     {
       "ice345/markdown-table-wrap.nvim",
       version = "v0.2.3",
       ft = { "markdown", "quarto", "rmd" },
       opts = {},
     },
   }
   ```

3. Run `:checkhealth markdown-table-wrap`.
4. Open one table-free Markdown file and one file with a table.
5. Confirm `require("markdown-table-wrap").version` reports `0.2.3`.
6. Confirm README and Vim help match the installed tag rather than unreleased
   `master` behavior.

## v0.2.3 Release Notes Draft

### markdown-table-wrap.nvim v0.2.3

v0.2.3 is a focused Inline rendering correction release.

Highlights:

- Linked semantic content highlights are background-transparent by default, so
  colorscheme backgrounds no longer turn every Inline cell into a filled
  rectangle. Add an explicit `bg` when a filled background is intentional.
- Inline-code delimiters inside link and image labels are removed before width
  calculation, keeping concealed backticks from shifting table separators.
- Regression coverage now exercises the linked-highlight background policy and
  code-wrapped links in rendered tables.

Known scope:

- Inline mode still depends on terminal/compositor behavior around conceal,
  virtual text, virtual lines, and soft wrapping. Reader remains the most stable
  view for wide tables.
- This patch release does not change the parser's supported Markdown dialect.

## v0.2.2 Release Notes Draft

### markdown-table-wrap.nvim v0.2.2

v0.2.2 is a stability and editor-coexistence release. It keeps the existing
Reader/Inline/Float workflow while making default setup less invasive and
large-document refreshes more predictable.

Highlights:

- Reader now automatically opens only when a supported buffer contains a table.
  Set `reader.auto_open = "always"` to retain the earlier all-document Reader
  behavior.
- `map_gx` now defaults to `false`, preserving native and user mappings in
  Source buffers. Table-aware link opening remains available through
  `:MarkdownTableOpenLink`, Reader links, or explicit opt-in.
- Interactive view state and deferred refresh work are isolated by buffer, so
  commands or edits in one document do not change another document's mode.
- Table discovery avoids the previous quadratic worst case on long runs of
  pipe-like text.
- Top-level parsing now accepts up to three spaces of indentation, missing-cell
  body rows, and arbitrary-length matching backtick spans while terminating
  safely at new Markdown block starts.
- Continuous border highlight spans reduce Reader extmark counts for large
  tables.
- Inline window options are restored when the view is cleared or left.
- Table highlight groups are reapplied after `:colorscheme` changes.
- Standard Neovim `rmd` filetype detection is supported, and public installation
  examples load `markdown`, `quarto`, and `rmd`.
- `get_buffer_config(bufnr)` and `get_preview_mode(bufnr)` expose effective
  per-buffer view configuration for integrations and diagnostics.
- Custom theme presets present on `master` after v0.2.1 are included in the
  patch release.

Known scope:

- Inline mode still depends on terminal/compositor behavior around conceal,
  virtual text, virtual lines, and soft wrapping. Reader remains the most stable
  view for wide tables.
- The parser targets common GFM pipe tables; broader GFM conformance and
  optional Tree-sitter discovery are planned for v0.3.
- The plugin remains table-focused and does not replace a general Markdown
  renderer.

## Future Releases

For every later release, replace the previous/next version values in this guide,
use the relevant milestone gate in [ROADMAP.md](ROADMAP.md), and repeat the same
sequence:

1. Freeze scope.
2. Align version, documentation, and tests.
3. Pass automation and the release-specific manual matrix.
4. Push the release commit to `origin/master` and wait for CI.
5. Create a new annotated tag.
6. Publish matching GitHub release notes.
7. Verify a clean installation from the public tag.
