# Publishing Guide

This is the maintenance and release procedure for the existing public
repository. The repository has already been created; do not reinitialize it or
rename its development branch as part of a release.

## Repository Facts

- Repository: `ice345/markdown-table-wrap.nvim`
- Remote: `origin` (`git@github.com:ice345/markdown-table-wrap.nvim.git`)
- Development/release branch: `master`
- Latest published tag before this release: `v0.2.3`
- Next planned release: `v0.3.0`
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

Before preparing v0.3.0:

1. Stop adding features not listed in the v0.3.0 CHANGELOG section.
2. Review every commit since the previous release:

   ```sh
   git log --oneline v0.2.3..master
   git diff --stat v0.2.3..master
   ```

3. Confirm each user-visible change has a regression test or a documented
   manual check.
4. Confirm the renderer still does not modify Markdown source text.
5. Move unfinished work to [ROADMAP.md](ROADMAP.md); do not describe it as part
   of the release.

## 2. Align Version And Documentation

For v0.3.0, all of the following must agree:

- `M.version` in `lua/markdown-table-wrap/init.lua`
- The top release in `CHANGELOG.md`
- README configuration/default behavior
- `doc/markdown-table-wrap.txt`
- The annotated Git tag `v0.3.0`
- The GitHub release title

Search for stale version/default references:

```sh
rg -n '0\.[0-9]+\.[0-9]+|map_gx|auto_open|your-name|ft = ' \
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

## 4. Run The v0.3.0 Manual Matrix

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
- Confirm Reader ordinary positions delegate custom callback/string/expr `gx`
  mappings exactly once and rendered targets do not also run the fallback.
- Open relative/absolute files, same-file/file anchors, wiki links, URLs,
  images, missing targets, and a cell with multiple targets from Reader and
  Float. Confirm relative paths use the Source directory.
- Confirm edit/split/vsplit/tab target strategies and one custom resolver.

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
- Confirm native `:bnext`, `:bprevious`, and `<C-^>` leave Reader without a
  listed scratch buffer or lost Source changes, including with `hidden` off.
- Confirm custom `H`/`L`, Bufferline, Telescope, and Harpoon transitions using
  explicit Reader passthrough or leave-then-delegate actions.
- Open the same Source in two windows with different widths. Confirm independent
  Readers, Source edit refresh, and cleanup after closing either Reader.
- Run `:MarkdownTableInspect`, `:MarkdownTableHelp`, and the statusline API in
  Source, Inline, Reader, and Float.

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

## 6. Tag v0.3.0

Create an annotated tag on the verified `master` commit:

```sh
git tag -a v0.3.0 -m "markdown-table-wrap.nvim v0.3.0"
git show --stat v0.3.0
git push origin v0.3.0
```

Never move or reuse a published tag. If a release contains a defect, prepare a
new patch release such as v0.3.1.

## 7. Publish The GitHub Release

Create a release from the existing tag:

```sh
gh release create v0.3.0 \
  --title "markdown-table-wrap.nvim v0.3.0" \
  --notes-file /path/to/release-notes.md
```

The notes should be derived from the v0.3.0 CHANGELOG entry. State explicitly
that existing v0.2 setup remains compatible, v0.2.4 work was folded into this
release, and no new Source mapping is enabled by default.

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
       version = "v0.3.0",
       ft = { "markdown", "quarto", "rmd" },
       opts = {},
     },
   }
   ```

3. Run `:checkhealth markdown-table-wrap`.
4. Open one table-free Markdown file and one file with a table.
5. Confirm `require("markdown-table-wrap").version` reports `0.3.0`.
6. Confirm README and Vim help match the installed tag rather than unreleased
   `master` behavior.

## v0.3.0 Release Notes Draft

### markdown-table-wrap.nvim v0.3.0

v0.3.0 makes Source, Inline, Reader, and Float operate as views of one
canonical Markdown Source while preserving the stable wide-table renderer.

Highlights:

- Reader `gx` safely falls back to the user's Source mapping, and normal buffer
  exits preserve unsaved Source state.
- Relative files, anchors, wiki links, URLs, images, split/tab opening, and
  custom resolvers work through one Source-aware target model.
- Configurable Reader/Float mappings, explicit passthrough, stable `<Plug>`
  actions, context/events, Inspect, Help, statusline, and expanded health
  diagnostics make every mode integratable and discoverable.
- Multiple Reader windows for one Source keep independent geometry and refresh
  from Source edits safely.
- Oversized inline-code tokens split by display width so narrow tmux panes keep
  table borders aligned.
- The headless suite covers 122 parser, renderer, navigation, mapping, link,
  lifecycle, multi-window, inspection, and compatibility cases.

Known scope:

- Inline remains dependent on terminal/compositor behavior around conceal,
  virtual text, virtual lines, and soft wrapping. Reader remains the stable
  view for very wide tables.
- Third-party Bufferline/Telescope/Harpoon workflows remain release-time manual
  checks; the plugin does not add those dependencies.

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
