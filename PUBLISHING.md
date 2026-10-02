# Publishing Guide

Release from the existing `ice345/markdown-table-wrap.nvim` repository on
`master`; remote `origin` is `git@github.com:ice345/markdown-table-wrap.nvim.git`.
Do not reinitialize the repository, rename its branch, or move a published tag.
The commands below prepare v1.0.0 from v0.9.0. For subsequent releases, select
the appropriate version and compare with the latest published tag first.
Check GitHub for publication status rather than treating this tagged document
as a live release ledger.

## 1. Choose Scope And Review

Patch: defects within the documented contract. Minor: compatible capabilities.
Major: breaking public behavior, options/defaults, mappings, APIs, or the
supported Neovim baseline, with migration notes. Releases follow concrete
problems and compatibility needs, not a feature quota or fixed schedule.

```sh
git remote -v
git branch --show-current
git fetch origin --tags
git status --short
gh release list --limit 5
git log --oneline v0.9.0..master
git diff v0.9.0 --stat
```

Review committed and uncommitted changes, preserving unrelated edits. Align
`M.version`, CHANGELOG, README, Vim help, and release notes. Use the actual
publication date, not a stale preparation date. v1.0.0 declares the existing
stable contract; it changes no runtime behavior or default mapping from 0.9.0.
Neovim 0.10+ remains the baseline. Keep known limitations explicit.

ROADMAP.md, AGENTS.md, CODEX_HANDOFF.md, and RELEASE.local.md are ignored
maintainer-local files. Do not force-add them. A fresh checkout must be able to
follow this guide without those files. Git mutations and publication require
maintainer authorization; an explicit request to publish authorizes this flow.

## 2. Automated Gates

Run on Neovim 0.10.4 and current stable from the repository root:

```sh
stylua --check .
git diff --check
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." -c "luafile tests/run.lua" -c "qa!"
nvim --headless -u NONE -c "helptags doc" -c "qa!"
nvim --headless -u NONE -c "set rtp+=." -c "help markdown-table-wrap" -c "qa!"
uv run --with pynvim python tests/ui_smoke.py
uv run --with pynvim python tests/ui_grid.py
```

Both Python runners accept `--nvim /absolute/path/to/nvim`. Where the personal
LazyVim integration is installed, also run `tests/ui_smoke.py --lazyvim`.
These test dependencies are not plugin runtime dependencies.

Run the parser benchmark for a release baseline; include the large Reader
profile for Reader/layout changes and stable milestones:

```sh
MARKDOWN_TABLE_WRAP_BENCH_READER=1 \
  nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." -c "luafile tests/benchmark.lua" -c "qa!"
```

Interpret measurements using [docs/performance.md](docs/performance.md).
Review generated help tags and relative links. Public docs must not require
maintainer-local files. Prior-release results do not verify new code.

## 3. Manual Release Matrix

Use [tests/README.md](tests/README.md) for the full applicable terminal matrix:
reading/editing/saving, narrow panes, CJK and wide code cells, configured
renderers, registers/undo, native navigation, and Source-relative links.

For Reader/diff work, use real saved Markdown files and typed commands:

1. Compare two different Sources with `:diffthis` and `:vert diffsplit`.
   Reader must yield to raw Source, preserve diff participation and visible
   hunks, and resume after `:diffoff!`. Include `auto_preview=false`.
2. Compare shared-Source Readers, a single diff window, and identical content.
   Each suspended window must resume independently, with its own viewport.
3. Move/edit Source while diffing: newer Source state must beat stale snapshots.
   Reader entry must refuse active diff; explicit disable/pause, closing a
   window, or wiping Source must prevent unwanted restoration.
4. Use `]c`, `[c`, `:diffupdate`, `:diffget`, and `:diffput`. Hunk edits must
   operate on Source. Unrelated Markdown windows must not be refreshed.

UI-attached input and grid checks do not verify terminal fonts/compositors.
Record runtime, OS, UI, cases, and failures. Do not imply native Windows or
Linux compositor coverage without evidence. If the maintainer explicitly
waives a manual gate for a particular release, record the waiver and missing
coverage in its verification record and notes. A waiver is not a passing test
and does not automatically apply to future releases.

## 4. Commit And Verify Exact-Commit CI

Stage only reviewed public files, inspect `git diff --cached`, and commit.
Suggested v1.0.0 message:

```text
release: stabilize the public contract for v1.0.0

Document 1.x API, configuration, mapping, event, and Source-model boundaries.
Keep v0.9.0 runtime behavior and the Neovim 0.10+ baseline unchanged.
Refresh release guidance, verification evidence, and maintenance policy.
```

Push normally to `origin/master`, then check:

```sh
gh run list --branch master --commit "$(git rev-parse HEAD)" --limit 5
gh run watch <run-id> --exit-status
```

Both Ubuntu jobs (Neovim 0.10.4 and stable) must pass for the exact release
commit. After any new commit, wait for its own CI before tagging.

## 5. Tag And Verify

```sh
git fetch origin --tags
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/master
git ls-remote origin refs/tags/v1.0.0
```

Require a clean reviewed `master`, equal commit IDs, and no existing local or
remote target tag. Once all gates pass (or an explicitly recorded manual waiver
applies), create a new annotated tag:

```sh
git tag -a v1.0.0 -m "markdown-table-wrap.nvim v1.0.0"
git show --stat v1.0.0
git push origin v1.0.0
gh run list --branch v1.0.0 --limit 5
gh run watch <tag-run-id> --exit-status
```

Require both tag CI jobs to pass. Never force or recreate a published tag.
A defect discovered after tagging needs a new appropriate version.

## 6. Verify Installation And Publish

Install from a fresh plugin-manager cache with `version = "v1.0.0"`. Confirm
its Git HEAD equals the reviewed commit and the Lua version is `1.0.0`.
Run `:checkhealth markdown-table-wrap`; check a table-free document, a table,
and one Reader/diff round trip. Do not substitute master for the tag.

Prepare `RELEASE.local.md` from CHANGELOG plus actual validation and limitations.
Review it, then publish from the existing remote tag:

```sh
gh release create v1.0.0 --verify-tag \
  --title "v1.0.0 — Stable Source-Backed Workflow" \
  --notes-file RELEASE.local.md
gh release view v1.0.0
```

No binary assets are required. Verify the release is public, is not a draft or
prerelease, and points to the reviewed tag. Refresh local handoff/roadmap state.
Do not move the tag to add after-publication records; use a later docs commit
if public corrections are needed.

## v1.0.0 Local Verification Record

macOS/Apple Silicon, 2026-10-02. Exact release-commit and tag CI are separate
required gates above, recorded in GitHub Actions; these are local results:

- 310 headless tests on Neovim 0.10.4 and 0.12.5.
- 64 clean-Neovim real-input checks and 8 UI-grid cases on each runtime.
- 65 personal LazyVim/Bufferline/Snacks real-input checks on 0.12.5.
- Additional UI-attached release probes on both runtimes: typed `:vert diffsplit`,
  nonzero diff-highlight attributes, `]c`, `:diffget`, `:diffput`, Reader refusal,
  and restoration, with automatic preview both enabled and disabled. These
  verify Neovim input/API state, not terminal font/compositor appearance.
- StyLua, whitespace, help tag generation/loading, and documentation links.
- Parser reference on 0.12.5: 10k prose 12.50 ms; 10k invalid pipe candidates
  150.52 ms; 500 tables 13.14 ms; 1k semantic rows 23.73 ms.
- Large Reader: 4,002 Source lines / 20,005 rendered lines; cold open 1,279.30 ms,
  cached full refresh 152.64 ms. GC-paused allocation profile: 1,110.96 MiB
  transient growth and 94.11 MiB retained after collection. This is not normal
  peak resident memory; timings and allocation figures are machine-specific.
- The maintainer explicitly accepted automated validation instead of the real
  terminal manual matrix for this release. No manual terminal font/compositor
  verification was performed. This exception does not waive future releases.
- Native Windows and Linux compositor execution remain unverified.

## v0.9.0 Verification Record

Verified locally on macOS/Apple Silicon, 2026-09-19:

- 310 headless tests pass on Neovim 0.10.4 and 0.12.5.
- Clean-Neovim UI-attached real-input checks: 64 pass on each runtime.
- Personal LazyVim/Bufferline/Snacks integration: 65 checks pass on 0.12.5.
- StyLua, whitespace checks, Vim help generation/loading pass.
- Neovim 0.12.5 parser benchmarks: 10k prose 14.13 ms, 10k invalid pipe
  candidates 155.70 ms, 500 small tables 21.97 ms, 1k semantic rows 28.68 ms;
  all within the documented reference budgets. These are machine-specific.

At the time of this pre-publication record, remaining checks were the
applicable terminal/manual matrix,
including visible diff hunks and `:diffsplit`; CI on the exact master release
commit and its new tag; and clean-tag installation after publication. Native
Windows and Linux compositor checks were not performed. No commit, push, tag,
or GitHub release was created during that local preparation. v0.9.0 was later
published at `02445d4c338fa0966f997d45b134d197b4605f5a` on 2026-09-20
(Asia/Tokyo). This historical record does not establish which remaining manual
checks were performed afterward.

## Historical Release Records

The records below describe earlier releases and are not v1.0.0 verification.

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
