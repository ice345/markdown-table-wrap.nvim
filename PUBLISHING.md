# Publishing Guide

Release procedure for the existing public repository. Do not reinitialize it,
rename its development branch, or move a published tag.

## Current Release Status

- Repository: `ice345/markdown-table-wrap.nvim`
- Remote: `origin` (`git@github.com:ice345/markdown-table-wrap.nvim.git`)
- Release branch: `master`
- Latest published release: `v0.8.0`, at
  `a5b676360946c7bce48c0b717ab05929761b88c8`.
- Prepared target: `v0.9.0` — Reader Diff Coexistence; not yet published.
- Supported Neovim baseline: 0.10+; CI matrix: Ubuntu × 0.10.4 and stable.

Verify remote state before release. Local planning in the ignored ROADMAP.md is
optional context; a fresh checkout can execute this guide without that file.
Do not count previous-release CI or manual results as evidence for new code.
Commit, push, tag, and publication each require maintainer authorization.

## 1. Review Scope And Align Documentation

```sh
git remote -v
git branch --show-current
git fetch origin --tags
git status --short
git log --oneline v0.8.0..master
git diff v0.8.0 --stat
```

Review both committed and uncommitted changes. Preserve unrelated local edits;
select only reviewed release files for the preparation commit. For v0.9.0:

- `M.version` must be `0.9.0`.
- CHANGELOG, README, Vim help, architecture, and the release notes must agree
  about Reader diff suspension, restoration, and manual-entry refusal.
- Set the top CHANGELOG release date to the actual publication date when ready
  to publish; do not leave a guessed past date or claim publication prematurely.
- Keep existing Inline/diff and Reader insertion-position limits explicit.
- ROADMAP.md, AGENTS.md, CODEX_HANDOFF.md, and RELEASE.local.md remain ignored
  local files. Do not force-add them to the release.

```sh
nvim --headless -u NONE -c "helptags doc" -c "qa!"
```

Review `doc/tags` if changed. Check relative documentation links; public docs
must not require a maintainer-local file to exist.

## 2. Automated Gates

From the repository root:

```sh
stylua --check .
git diff --check
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." -c "luafile tests/run.lua" -c "qa!"
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." -c "luafile tests/benchmark.lua" -c "qa!"
nvim --headless -u NONE -c "set rtp+=." -c "help markdown-table-wrap" -c "qa!"
```

Run the suite with Neovim 0.10.4 and stable. Local `.agent/check.sh` and
`.agent/check-perf.sh` are optional conveniences, not dependencies of this guide.
Interpret benchmark results using [docs/performance.md](docs/performance.md).

For lifecycle/input changes, use the UI-attached runner:

```sh
uv run --with pynvim python tests/ui_smoke.py
uv run --with pynvim python tests/ui_smoke.py --nvim /absolute/path/to/nvim-0.10.4
```

Where the personal LazyVim integration is installed, also run:

```sh
uv run --with pynvim python tests/ui_smoke.py --lazyvim
```

See [tests/README.md](tests/README.md) for coverage and the complete manual
matrix. Grid tests are additionally relevant when changing geometry/overlays.

## 3. v0.9.0 Manual Release Matrix

Use real saved Markdown files and type commands in a terminal:

1. Open two different Sources as Readers. Enter `:diffthis` in each; both must
   show raw Source with correct hunk highlighting and remain diff participants.
   `:diffoff!` must restore each Reader without pausing Source.
2. Repeat with `auto_preview=false` and manually opened Readers.
3. Open the same Source in two Readers. Diff just one, then both; after leaving
   diff, each suspended window must restore independently. Also test a single
   diff window and identical-content comparisons.
4. Start in a long wrapped table with a nonzero cursor column and scroll offset.
   An unchanged diff round trip must restore the correct window's view. Moving
   or editing Source during diff must take precedence over a stale snapshot.
5. In diff, invoke `:MarkdownTableToggleReader`; Source and diff must remain
   intact. Explicitly disable automatic preview; leaving diff must not reopen
   Reader. Closing the window or wiping Source must not resurrect it.
6. Run `:diffupdate`, `:diffget`, and `:diffput` with an unrelated Markdown
   window present. That window must not be refreshed merely because hunks
   changed. Hunk changes must apply to raw Source, never rendered table borders.
7. Exercise `:diffsplit` as well as `:diffthis` to check deferred transitions.
8. Recheck normal reading/editing/saving, native buffer navigation, and the
   applicable integration checks in tests/README.md.

UI-attached automated input checks do not prove terminal font/compositor or
hunk appearance. Record runtime, OS, terminal/UI, tested cases, and failures.
Windows native execution and Linux compositor verification remain unrun unless
new evidence is recorded; absence of issues is not verification.

## 4. Commit And Verify CI On master

Suggested commit message for the complete v0.9.0 preparation:

```text
fix(reader): preserve window-local Reader state across diff mode

Suspend Reader to canonical Source while a window is diffing and restore
that window after diff ends, including manual and shared-Source Readers.
Reject Reader entry during diff without changing Source or preview policy.
Handle diff transitions that do not emit DiffUpdated at the safe input boundary.

Add lifecycle and real-input regressions, strengthen viewport and hunk-update
checks, and prepare the v0.9.0 documentation and release notes.

Refs #9
```

Use `Refs #9`: the PR was closed and this is an in-tree implementation, not a
claim that its original patch was merged unchanged. Stage the reviewed public
files explicitly, inspect `git diff --cached`, then commit and push only when
ready and authorized. The ignored roadmap does not belong in this commit.

After the preparation commit is pushed normally to `origin/master`:

```sh
gh run list --branch master --commit "$(git rev-parse HEAD)" --limit 5
gh run watch <run-id> --exit-status
```

Both Neovim matrix jobs must pass for that exact commit. If anything changes,
repeat relevant checks and wait for CI on the new commit before tagging.

## 5. Create A New Annotated Tag

Only after the release gates above are satisfied:

```sh
git fetch origin --tags
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/master
```

Require a clean `master` and matching commit IDs. Check that `v0.9.0` is not
already published; never force or recreate an existing tag.

```sh
git tag -a v0.9.0 -m "markdown-table-wrap.nvim v0.9.0"
git show --stat v0.9.0
git push origin v0.9.0
```

Check tag CI as well:

```sh
gh run list --branch v0.9.0 --limit 5
gh run watch <tag-run-id> --exit-status
```

If a pushed tag reveals a defect, keep the tag immutable and prepare the next
appropriate version. Do not publish notes claiming failed checks passed.

## 6. Publish The GitHub Release

Copy the v0.9.0 notes below to `RELEASE.local.md` (ignored), review them against
the final CHANGELOG, then publish from the existing remote tag:

```sh
gh release create v0.9.0 --verify-tag \
  --title "v0.9.0 — Reader Diff Coexistence" \
  --notes-file RELEASE.local.md
```

No compiled archive or binary asset is required. lazy.nvim installs from the
Git tag. Do not substitute an unreleased branch for the verified tag.

## 7. Verify Publication

- Confirm the release tag points to the reviewed commit.
- Install using `version = "v0.9.0"` from a clean plugin-manager cache.
- Confirm `require("markdown-table-wrap").version` reports `0.9.0`.
- Run `:checkhealth markdown-table-wrap`, open a table-free document and a
  document with a table, and check one Reader/diff round trip.
- Update the current-release status above after publication. Preserve actual
  verification evidence; do not describe future gates as completed work.

## v0.9.0 Release Notes Draft

v0.9.0 makes Reader coexist with Neovim diff mode while keeping the original
Markdown Source authoritative.

### Fixed

- Entering diff in a Reader window temporarily shows its Source and preserves
  the Reader view snapshot. The Source is re-registered for diff after the swap.
- Leaving diff restores each suspended Reader independently, including manually
  opened Readers with `auto_preview=false` and windows sharing one Source.
- Single-window and identical-content comparisons are detected even when no
  `DiffUpdated` event is emitted. Ordinary hunk updates do not trigger unrelated
  Markdown window refreshes.
- Reader commands refuse to open in an active diff window, preserving the
  comparison and preview policy. Explicit pause/disable and window/Source cleanup
  prevent unwanted restoration.

### Compatibility and scope

No configuration migration is required. Existing command names, Plug mappings,
Lua action names, and User event names are unchanged. Neovim 0.10+ remains the
baseline, and automatic rendering never rewrites Source.

Existing Inline overlays are buffer-scoped and are not suspended per diff
window. Reader insertion keys still map table-cell positions to the Source cell
start; use `cic` or `:MarkdownTableEditCell` for explicit cell editing.

Thanks for the reproduction and Source/diff investigation in #9.


## v0.9.0 Verification Record

Verified locally on macOS/Apple Silicon, 2026-09-19:

- 310 headless tests pass on Neovim 0.10.4 and 0.12.5.
- Clean-Neovim UI-attached real-input checks: 64 pass on each runtime.
- Personal LazyVim/Bufferline/Snacks integration: 65 checks pass on 0.12.5.
- StyLua, whitespace checks, Vim help generation/loading pass.
- Neovim 0.12.5 parser benchmarks: 10k prose 14.13 ms, 10k invalid pipe
  candidates 155.70 ms, 500 small tables 21.97 ms, 1k semantic rows 28.68 ms;
  all within the documented reference budgets. These are machine-specific.

Still required for publication: the applicable terminal/manual matrix above,
including visible diff hunks and `:diffsplit`; CI on the exact master release
commit and its new tag; and clean-tag installation after publication. Native
Windows and Linux compositor checks were not performed. No commit, push, tag,
or GitHub release was created during this local preparation.

## Historical Release Records

The records below describe earlier releases and are not v0.9.0 verification.

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

## v0.7.0 Release Notes

### markdown-table-wrap.nvim v0.7.0

v0.7.0 unifies derived-view lifecycle around canonical Source identity and
adds source-safe blockquote table support without changing the plugin's core
non-destructive rendering contract.

Highlights:

- Source, Inline, Reader, and Float commands resolve through one canonical
  Source identity. Reader-to-Float transitions survive refresh debounce, and
  closing Float restores the originating Source/Reader/Inline view, logical
  cell, cursor, and viewport when still valid.
- Temporary next/previous/alternate/selected-buffer navigation no longer
  permanently pauses automatic Reader mode. Default navigation keys remain
  conservative, with `H`/`L` passthrough opt-in.
- Top-level and nested blockquote tables render with visible quote depth and
  exact Source spans. Reader cell edits and explicit formatting preserve the
  container; unsupported list-contained tables remain untouched.
- Compact GFM delimiter cells are accepted, and rejected table-like
  candidates no longer hide a later valid table in the same discovery range.
- Reader and standalone Float link opening share the external-scheme
  allowlist. Home-relative paths avoid expression-expanding path logic,
  scrolling uses resolved termcodes, and externally closed Float state is
  cleaned up.
- Hot paths reuse read-only cached models, skip unchanged theme work, and
  avoid rebuilds for plain scrolling while public model boundaries continue
  to return isolated values.
- README, Vim help, architecture, performance guidance, types, health,
  contributor guidance, CI, changelog, and license metadata were aligned with
  the released behavior.

Verification:

- 249 headless tests passed on Neovim 0.10.4 and stable 0.12.5.
- The real LazyVim multi-buffer matrix passed 28/28 assertions, and the Reader
  `:w`, `:wq`, `:x`, and `ZZ` matrix passed 15/15 assertions.
- Parser and large-Reader reference benchmarks stayed within their documented
  budgets.
- GitHub Actions passed both supported Neovim jobs for the `master` release
  commit and again for the annotated `v0.7.0` tag.

Release: <https://github.com/ice345/markdown-table-wrap.nvim/releases/tag/v0.7.0>

## v0.8.0 Release Notes

### markdown-table-wrap.nvim v0.8.0

v0.8.0 is a broad correctness and lifecycle release. It keeps Source as the
only canonical document while making disposable Reader views safer across
external buffer deletion, native writes, session restoration, rapid editing,
Unicode geometry, and malformed Markdown.

Highlights:

- Deleting a Reader-backed Source through native commands or
  Snacks/Bufferline now disposes every dependent Reader without leaving blank
  zombie views, losing unrelated buffers, or turning temporary navigation into
  an explicit pause.
- Reader file saves, ranges, append, bang, `++` arguments, save-as, rename, and
  session restoration resolve through Source. Modified restoration placeholders
  remain protected for recovery instead of becoming editable shadow documents.
- Reader insert handoff, `cic`, Source-backed undo/redo/repeat, registers,
  mutation validation, and unsafe structural-pipe refusal are hardened against
  stale state and fast input.
- Pipe/code-span parsing, quoted fences, conservative list containment,
  Tree-sitter fallback, nested inline spans, paths, theme presets, CSV export,
  and failure diagnostics have explicit tested boundaries.
- Window text-area measurement, wide and combining characters, trailing spaces,
  tabs, Visual overlays, conceal/virtual text, and refresh signatures now share
  display-width-aware behavior.

Verification:

- 298 headless tests pass on Neovim 0.10.4 and stable 0.12.5.
- The personal LazyVim integration passes 60 real-input checks using the actual
  Bufferline/Snacks close callback; the clean-Neovim matrix passes 59 checks.
- Eight UI-grid selection cases pass on both supported test runtimes, covering
  CJK, combining marks, tabs, character/block selection, and horizontal scroll.
- Parser benchmarks remain within the documented reference budgets.

Known boundary:

- Native `:write !cmd` and filters stream the rendered current buffer because
  Neovim bypasses file-write hooks for that shell path. Enter Source first when
  raw Markdown must be sent to a command.
