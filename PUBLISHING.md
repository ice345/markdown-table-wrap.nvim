# Publishing Guide

This is the maintenance and release procedure for the existing public
repository. The repository has already been created; do not reinitialize it or
rename its development branch as part of a release.

## Repository Facts

- Repository: `ice345/markdown-table-wrap.nvim`
- Remote: `origin` (`git@github.com:ice345/markdown-table-wrap.nvim.git`)
- Development/release branch: `master`
- Latest published tag: `v0.6.0`
- Current local release candidate: `v0.7.0`; it is not published until the
  maintainer explicitly approves the final diff and release gates.
- Supported Neovim baseline: 0.10+

Verify these values rather than assuming the local checkout is current:

```sh
git remote -v
git branch --show-current
git fetch origin --tags
git status --short
git tag --sort=-version:refname | head
```

The v0.4.0 section below is the retained release record and checklist example;
the same gates apply to v0.7.0 and later releases. Substitute the target
version and milestone scope from the maintainer-local `ROADMAP.md`. Release
only from `master`, with no unrelated local changes, after the branch is up to
date with `origin/master`.

## Historical v0.4.0 Checklist

Before preparing v0.4.0:

1. Stop adding features not listed in the v0.4.0 CHANGELOG section.
2. Review every commit since the previous release:

   ```sh
   git log --oneline v0.3.0..master
   git diff --stat v0.3.0..master
   ```

3. Confirm each user-visible change has a regression test or a documented
   manual check.
4. Confirm the renderer still does not modify Markdown source text.
5. Move unfinished work to the maintainer-local `ROADMAP.md`; it is intentionally
   ignored and is not part of the public plugin checkout.

## 2. Align Version And Documentation

For v0.4.0, all of the following must agree:

- `M.version` in `lua/markdown-table-wrap/init.lua`
- The top release in `CHANGELOG.md`
- README configuration/default behavior
- `doc/markdown-table-wrap.txt`
- The annotated Git tag `v0.4.0`
- The GitHub release title

Search for stale version/default references:

```sh
rg -n '0\.[0-9]+\.[0-9]+|map_gx|auto_open|your-name|ft = ' \
  README.md CHANGELOG.md PUBLISHING.md doc lua tests
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

## 4. Run The v0.4.0 Manual Matrix

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
- Leave an automatically opened Reader through native buffer navigation, return
  to its Source, and confirm Reader reopens. Explicit close/edit must still
  report `paused=true` and remain in Source.
- Run `tests/benchmark.lua`, compare all scenarios with
  `docs/performance.md`, and inspect the selected discovery backend and cache
  stages with `:MarkdownTableInspect`.

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
  explicit Reader passthrough or leave-then-delegate actions. Returning to an
  unpaused Source must restore its Reader cursor and viewport; explicit close
  must remain in Source.
- Open the same Source in two windows with different widths. Confirm independent
  Readers, Source edit refresh, and cleanup after closing either Reader.
- Run `:MarkdownTableInspect`, `:MarkdownTableHelp`, and the statusline API in
  Source, Inline, Reader, and Float.

### Parsing, Performance, Theme, And Filetypes

- Confirm fenced table-shaped text is ignored, including backtick and tilde
  fences.
- Confirm escaped pipes and pipes inside single/multiple-backtick code spans.
- Confirm compact one-hyphen GFM delimiter cells are accepted, while malformed
  delimiter rows and adjacent pipe-like prose are rejected.
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

## 6. Tag v0.4.0

Create an annotated tag on the verified `master` commit:

```sh
git tag -a v0.4.0 -m "markdown-table-wrap.nvim v0.4.0"
git show --stat v0.4.0
git push origin v0.4.0
```

Never move or reuse a published tag. If a release contains a defect, prepare a
new patch release such as v0.4.1.

## 7. Publish The GitHub Release

Create a release from the existing tag:

```sh
gh release create v0.4.0 \
  --title "markdown-table-wrap.nvim v0.4.0" \
  --notes-file /path/to/release-notes.md
```

The notes should be derived from the v0.4.0 CHANGELOG entry. State explicitly
that the v0.3 mode/action contract remains compatible, Lua discovery remains
the guaranteed path, and no new Source mapping is enabled by default.

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
       version = "v0.4.0",
       ft = { "markdown", "quarto", "rmd" },
       opts = {},
     },
   }
   ```

3. Run `:checkhealth markdown-table-wrap`.
4. Open one table-free Markdown file and one file with a table.
5. Confirm `require("markdown-table-wrap").version` reports `0.4.0`.
6. Confirm README and Vim help match the installed tag rather than unreleased
   `master` behavior.

## v0.4.0 Release Notes Draft

### markdown-table-wrap.nvim v0.4.0

v0.4.0 gives every table, row, cell, delimiter, and inline token an exact
Source-backed identity, then uses that model for safer GFM parsing, optional
discovery backends, and bounded refresh work.

Highlights:

- Source-spanned table and token models survive normalization, wrapping,
  resizing, refresh, and multiple links in one cell.
- Reference links, balanced destinations, autolinks, nested inline semantics,
  arbitrary code delimiters, and the classified GFM corpus improve correctness.
- `auto`, `lua`, and optional `treesitter` discovery are inspectable and fail
  safely; the deterministic Lua backend remains the default.
- Parse/layout caches invalidate by changedtick and window/config signatures,
  expose diagnostics, and release all entries on wipe.
- Native buffer navigation no longer sets `paused=true`, so returning to an
  auto-preview table Source restores Reader.
- The headless suite covers 134 parser, renderer, metadata, discovery, cache,
  navigation, mapping, link, lifecycle, and compatibility cases.

Known scope:

- Inline remains dependent on terminal/compositor behavior around conceal,
  virtual text, virtual lines, and soft wrapping. Reader remains the stable
  view for very wide tables.
- Third-party Bufferline/Telescope/Harpoon workflows remain release-time manual
  checks; the plugin does not add those dependencies.

## v0.5.0 Release Notes Draft

### markdown-table-wrap.nvim v0.5.0

v0.5.0 turns the plugin into a Source-backed Table Workbench while keeping
automatic rendering read-only.

Highlights:

- Source-aware Reader cell operations (`yic`, `vic`, `dic`, `cic`, `cip`, and
  contextual `c`) preserve Markdown semantics and native Visual behavior.
- Semantic rendered-cell/table copy and TSV/CSV export keep Source copy
  explicitly distinct and do not mutate the document.
- Wide-table policies add an opt-in column viewport, deterministic hidden
  markers, and per-column width/priority rules while retaining wrap as the
  default.
- Reader ergonomics include optional sticky headers, indexed cell lookup, and
  explicit status/help context for large documents.
- Source editing commands format tables, add/delete/move rows and columns,
  cycle alignment, and edit a long cell in a focused popup. Every successful
  rewrite is one undo step and malformed excess-cell tables are refused.

Verification for the release candidate:

- 165 headless regression tests pass on the local Neovim 0.12.4 runtime.
- The reference benchmark measured about 1.51 s cold Reader open, 0.31 s full
  refresh, and 43 ms for 500 `gg`/`G` pairs on the 4,002-line/20,005-line
  large-Reader fixture. CI remains the authority for Neovim 0.10.4 and stable.
- The manual terminal/compositor matrix remains required for release review,
  especially narrow panes, CJK/code cells, third-party renderer coexistence,
  and Source popup editing.

## v0.5.1 Release Notes Draft

### markdown-table-wrap.nvim v0.5.1

v0.5.1 is a focused Reader interaction patch for the Source-backed cell
workbench introduced in v0.5.0.

Highlights:

- `yic`, `dic`, and `vic` now use Vim's real operator-pending/Visual
  text-object phases instead of relying on conflicting complete Normal-mode
  mappings.
- CJK, wide icons, links, and inline code keep each `vic` overlay and yank
  inside the selected logical cell; neighboring columns and `│` borders are
  excluded.
- Temporary Visual `y` handling restores an existing user mapping when the
  selection ends or Reader is closed.

Verification:

- 168 headless regression tests pass on local Neovim 0.12.4, including the
  provided CrossOver/Proton/Wine/Parallels-style CJK/link fixture.
- The large Reader reference run remains 4,002 Source lines → 20,005 Reader
  lines: approximately 1.45 s cold open, 0.315 s refresh, and 42 ms for 500
  `gg`/`G` pairs on the development machine.
- The supported Neovim 0.10.4/stable CI matrix and the manual terminal matrix
  remain release gates.

## v0.6.0 Release Notes

### markdown-table-wrap.nvim v0.6.0

v0.6.0 hardens Reader's Source-backed Vim semantics and failure boundaries
without changing the canonical-Source architecture.

Highlights:

- `yic`, `dic`, `cic`, and logical `vic` operators now honor selected,
  small-delete, yank-zero, and black-hole registers. Cell change is one undo
  block, and logical `.` survives the matching undo/redo sequence.
- Reader guards its `y` and `d` cell prefixes: mistyped motions such as
  `yj`/`yk` cannot copy rendered borders, while `dj`/`dk`/`dd` no longer raise
  E21. Native rendered copy remains available through Visual selection.
- Native Source `c` motions, including `cip`, remain reachable. Cell put moves
  to `:MarkdownTablePutCell` by default, with the previous `cip` behavior
  retained as an explicit opt-in mapping.
- Reader cell, link, context, fallback, and export operations use narrow
  snapshots instead of deep-copying the full rendered document; indexed cell
  refocus remains bounded on large tables.
- Failed Reader open/refresh transitions roll back ownership, indexes,
  changedticks, overlays, and protected-buffer state. Scheduled refresh errors
  are contained, and resize refresh reaches every affected visible Reader.
- Configuration normalization and command/`<Plug>` registration now live in
  focused modules instead of expanding the lifecycle orchestrator.

Verification:

- 196 headless regression tests pass on Neovim 0.10.4 and 0.12.4, including
  the complete CrossOver/Proton/Wine virtualization table, registers, counts,
  macros, undo/redo, dot repeat, guarded typo sequences, lifecycle rollback,
  resize fanout, and configuration isolation.
- The parser reference benchmark on Neovim 0.12.4 measured about 26 ms for 10k
  prose lines, 164 ms for 10k invalid pipe candidates, 22 ms for 500 small
  tables, and 29 ms for 1k semantic rows.
- The 4,002-Source-line/20,005-Reader-line reference remains fully
  materialized: approximately 1.44 s cold open, 0.307 s refresh, 42 ms for 500
  `gg`/`G` pairs, and 2.1 ms for 500 indexed local-cell reads on the
  development machine.

## Future Releases

For every later release, replace the previous/next version values in this guide,
use the relevant milestone gate in the maintainer-local roadmap, and repeat the
same sequence:

1. Freeze scope.
2. Align version, documentation, and tests.
3. Pass automation and the release-specific manual matrix.
4. Push the release commit to `origin/master` and wait for CI.
5. Create a new annotated tag.
6. Publish matching GitHub release notes.
7. Verify a clean installation from the public tag.
