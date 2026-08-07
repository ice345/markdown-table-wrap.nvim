# Development Roadmap

This roadmap begins after v0.2.3. It describes the product contract as well as
the implementation order. It is written for two audiences:

- Users should be able to see which daily workflows become easier and what
  compatibility guarantees a release provides.
- Contributors should be able to implement one bounded work package at a time,
  with explicit dependencies, tests, and completion criteria.

The ordering is user-first. Parser or renderer work moves ahead of interaction
work only when it is a proven prerequisite. Every package must remain feasible
inside the current pure-Lua parser, renderer, extmark, and scratch-buffer
architecture; a rewrite is not a milestone.

## Delivery Status

- The v0.2.4 compatibility work is complete and is included in v0.3.0 rather
  than published as a separate intermediate tag.
- All v0.3.1-v0.3.5 work packages are complete in v0.3.0. These numbers are
  implementation checkpoints inside the v0.3 milestone, not SemVer releases.
- The automated v0.3 gate currently contains 122 headless tests. The
  terminal/compositor and third-party navigation matrix remains a release-time
  manual gate because those behaviors cannot be proven in headless Neovim.
- v0.4 and later sections remain planned work; their order may change only
  with documented user evidence or a prerequisite discovered during delivery.

## Product Direction

`markdown-table-wrap.nvim` is a table-focused view and interaction layer for
Markdown. It is not a second general-purpose Markdown renderer and it must not
take ownership of unrelated Markdown behavior.

The central product promise is:

> Changing the table view may change how a document is displayed, but it must
> not unexpectedly change the user's normal Neovim navigation, mappings,
> source identity, or ability to return to the Markdown source.

Convenience means all of the following:

- Zero-configuration table reading is stable in a normal terminal.
- The original Markdown buffer remains the only source of truth.
- Existing mappings are preserved or receive a documented safe fallback.
- File, URL, buffer, window, and tab navigation behave relative to the Source
  buffer even while Reader is visible.
- The current mode and the way back to Source are always discoverable.
- Unsupported behavior fails locally and explains the available alternative.
- Advanced configuration is optional; common workflows do not require users to
  understand extmarks, conceal, scratch buffers, or internal state tables.

## Mode Model

Source, Inline, and Reader are the three user-facing document states. Float is
an auxiliary table inspector rather than a long-lived document state.

### Source — Canonical Editing State

Source is the real Markdown buffer. It owns the file name, modified flag,
undo/redo history, marks, jumplist entries, diagnostics, LSP attachment,
buffer-local mappings, and integration with other plugins.

Source is responsible for:

- Complete Markdown editing and structural table editing.
- Native and user-defined navigation such as `gf`, `gx`, buffer switching,
  Telescope, Harpoon, marks, folds, and window commands.
- All source-changing table commands.
- Providing the canonical path used to resolve relative links.

Source is not a renderer backend. It is the baseline state that exists when no
persistent rendered view is active. Rendering must never silently rewrite it.

### Inline — Source-Preserving Editing View

Inline keeps the real Source buffer in the window and adds a rendered table
layer with extmarks, virtual text, conceal, and optional virtual lines.

Inline is intended for:

- Users who want to edit and navigate the original Markdown without leaving
  the Source buffer identity.
- Short or moderately wide tables where an in-place visual layer is useful.
- Workflows that depend heavily on LSP, Git signs, diagnostics, marks,
  buffer-local mappings, or other Source-buffer integrations.

Inline must preserve:

- Source buffer identity and all user/plugin mappings.
- Source cursor semantics and the normal undo/modified state.
- Window options after Inline is cleared or the window leaves the buffer.
- A predictable reveal-on-edit path for Insert and Visual modes.

Inline has unavoidable constraints that must remain explicit:

- Rendered rows are visual objects, not real buffer lines.
- Copying in Source/Inline copies Markdown source, not a reconstructed rendered
  table.
- Soft wrap, conceal, virtual lines, terminal shaping, and competing extmarks
  can produce platform-specific behavior.
- Reader is the stability fallback when those constraints matter more than
  direct editing.

### Reader — Stable Source-Backed Reading View

Reader is a protected, real-line projection of the Source document. It exists
to make wide tables stable to read, search, select, and copy without exposing
wrapped source rows beneath an overlay.

Reader is intended for:

- Stable full-document reading when tables are wider or taller than the Source
  representation.
- Selecting and copying rendered Unicode table lines.
- Following links and moving through a document without first returning to raw
  Markdown.
- Temporarily entering Source at the closest meaningful source position when an
  edit is requested.

Reader is internally implemented with a scratch buffer, but that is an
implementation detail. Its public behavior must remain anchored to the Source
buffer. Reader must therefore:

- Resolve files and links relative to the Source path, never the synthetic
  Reader URI.
- Preserve or safely delegate user navigation mappings.
- Support normal buffer/window/tab transitions without stranding hidden Source
  state or adding duplicate history entries.
- Report the Source buffer to integrations through a stable context API and
  documented `User` events.
- Keep read-only actions in Reader and return to Source only for editing or
  actions that require a real buffer transition.
- Restore Source cursor, window options, `bufhidden`, modified state, and pause
  policy deterministically on every exit path.

Reader is not expected to make every arbitrary Source-only plugin operate on
the scratch buffer. Instead, it must provide a reliable Source context,
mode-agnostic actions, configurable mappings, and a safe leave-then-delegate
path.

### Float — Temporary Focused Inspector

Float displays one rendered table for focused inspection. It is intentionally
ephemeral and should not be treated as a peer to Source, Inline, and Reader in
state management.

Float is intended for:

- Inspecting one table without changing the underlying document view.
- Following a table link or reading a long cell in a compact window.
- A manually requested preview, not an automatically reopened editing state.

Opening and closing Float must preserve the underlying Source or Inline state,
cursor, and window options. Float mappings should be minimal, configurable, and
fully disableable.

## Mode Comparison

| User need | Recommended state | Buffer identity | What copying returns | Primary limitation |
| --- | --- | --- | --- | --- |
| Edit Markdown or table syntax | Source | Real Source | Markdown source | No wrapped table rendering |
| Edit while seeing rendered tables | Inline | Real Source | Markdown source | Extmark/conceal/wrap constraints |
| Read, search, select, and copy stable tables | Reader | Source-backed projection | Rendered text | Requires explicit Source-context bridging |
| Inspect one table temporarily | Float | Temporary inspector | Rendered table text | Not a full document workflow |

The public documentation should recommend a state by task, not present all
options as equivalent toggles.

## Cross-Mode Contracts

These contracts apply to every future release.

### 1. Source Is The Only Truth

- Automatic rendering never changes Source lines.
- Reader and Float never become independent editable copies.
- Every path, modified flag, save, edit, and resolver action targets Source.
- Source deletion, rename, unload, or invalidation cleans up dependent views.

### 2. Actions Have One Meaning Across Modes

Commands and future `<Plug>` mappings should route through mode-agnostic
actions. An action determines the active context and chooses one of three paths:

1. Execute inside the current view when the action is safe there.
2. Resolve against Source metadata while keeping the current view.
3. Restore Source, then delegate when a real buffer/editing context is needed.

Separate implementations must not make `open_link`, `edit`, `next_buffer`, or
`refresh` mean different things in Source and Reader.

### 3. Mappings Are Non-Invasive

- Default setup does not overwrite unrelated global or buffer-local mappings.
- A Reader mapping consumes a key only when it can perform its documented
  action; otherwise it invokes the captured user/native fallback when safe.
- Callback, string, expression, remap, `replace_keycodes`, and buffer-local
  mappings remain valid fallback cases.
- Reader and Float mappings become configurable and disableable.
- `<Plug>` mappings are the stable integration layer; suggested user keys stay
  examples rather than mandatory defaults.
- The plugin must not bind `H`, `L`, `gf`, or other common navigation keys by
  default merely to work around Reader internals.

### 4. Link And File Navigation Uses Source Context

- `https:`, `http:`, and other external URI schemes use a validated external
  opener.
- Relative and absolute file targets open inside Neovim by default.
- Relative paths are based on the Source file directory.
- Same-document anchors, file anchors, wiki links, images, and reference links
  have explicit resolver behavior.
- `gf`, `gF`, split/tab variants, and `gx` share target classification but may
  use different open strategies.
- User resolver callbacks are validated and cannot interpolate targets into
  shell commands.

### 5. State Has An Explicit Owner

- Source-level preferences such as selected persistent view and auto-preview
  policy are keyed by Source buffer.
- Inline layout and saved options are keyed by Source buffer and window where
  geometry differs.
- Reader projection, width, cursor mapping, and window options are keyed by a
  Reader session and window, with a reference to Source.
- Float state is keyed by its own window and discarded on close.
- Repeated `setup()`, buffer wipe, window close, and session transitions leave
  no timers, mappings, extmarks, or scratch buffers behind.

### 6. Transitions Are Deterministic

| Transition | Required behavior |
| --- | --- |
| Source → Inline | Keep the same buffer/cursor and add only the visual layer |
| Inline → Source | Remove extmarks and restore every changed window option |
| Source/Inline → Reader | Clear Inline safely, create a Source-backed session, and map the cursor |
| Reader → Source | Restore the exact available Source position and window state |
| Reader → Inline | Return to Source first, then enable Inline without changing global defaults |
| Reader → another buffer/window/tab | Restore Source state, then perform the requested navigation once |
| Any persistent state → Float | Preserve the underlying state and return to it on close |

### 7. Compatibility Comes From Contracts, Not Adapters

The plugin should not acquire hard dependencies on Bufferline, Telescope,
Harpoon, statusline plugins, or `render-markdown.nvim`. It should expose Source
context, `<Plug>` actions, callbacks, and events that let those tools keep their
normal behavior. Native Neovim commands are automated tests; representative
third-party workflows are manual compatibility checks.

## User Journeys Used As Release Tests

Every milestone must identify which journeys it improves and must not regress
the others.

1. Open a Markdown file with no table and remain in Source under the default
   `reader.auto_open = "has_table"` policy.
2. Open a table document and read every table without moving the cursor to each
   table first.
3. Use `gf`/`gF` on a relative `[label](path.md)` target and open it relative to
   the Source file.
4. Use `gx` on a URL, and use the pre-existing `gx` mapping when no supported
   link is under the cursor.
5. Use custom `H`/`L`, native `:bnext`/`:bprevious`, `<C-^>`, a split, a tab,
   Telescope, or Bufferline without leaving stale Reader/Source state.
6. Enter Source from a wrapped Reader cell, edit, save, and return to the same
   logical place.
7. Search and yank in Reader while preserving rendered text; search and yank in
   Source/Inline while preserving source semantics.
8. Show the same Source in two differently sized windows without sharing
   mutable layout state.
9. Change the Source from another window and refresh every dependent Reader
   without rewriting the file.
10. Disable all plugin mappings and control the plugin only through commands,
    Lua APIs, or `<Plug>` mappings.
11. Wipe, rename, save-as, or unload Source and leave no invalid scratch buffer,
    timer, mapping, or changed window option.
12. Use a custom colorscheme and semantic highlights without unexpected cell
    backgrounds or border drift.

## Development Architecture

The current parser, renderer, Inline extmark implementation, Reader projection,
and setup module remain the foundation. Development should be incremental.

Expected internal boundaries:

- `parser.lua`: source discovery and the normalized table model.
- `markdown.lua`: display tokens and link/source metadata.
- `render.lua`: width allocation and mode-independent rendered line objects.
- `inline.lua`: Source-buffer visual projection only.
- `reader.lua`: Reader buffer construction and session lifecycle only.
- `context.lua` (planned): resolve Source/view/window identity for any action.
- `actions.lua` (planned): mode-agnostic edit, view, navigation, refresh, and
  buffer-transition actions.
- `links.lua` (planned): classify, resolve, and open URL/file/anchor/wiki targets.
- `mappings.lua` (planned): `<Plug>` registration, configured mappings, capture,
  fallback, and restoration.
- `inspect.lua` (planned): read-only state and parser/layout diagnostics.

`init.lua` should gradually become orchestration and public API registration
rather than continuing to accumulate view-specific behavior.

Architecture rules:

- Do not copy every Source mapping into Reader. Proxy only documented actions
  or explicitly configured passthrough keys.
- Do not make Reader listed merely to satisfy a bufferline; that creates a
  duplicate user-visible buffer identity.
- Do not run arbitrary user mappings in the synthetic Reader path context.
- Do not introduce Tree-sitter as a requirement.
- Do not replace the renderer while interaction work can reuse its existing
  line objects and link metadata.
- Add source spans gradually, beginning with links and navigation targets, then
  full cell identity.

## Completed Baseline — v0.2.3

Future work must preserve the following completed behavior:

- Source is never rewritten by rendering.
- Reader, Inline, and Float render the same table layout model.
- Reader is the stable default view when a supported buffer contains a table;
  plain Markdown stays in Source by default.
- Reader supports rendered selection/yank, Source edit entry, Source save
  forwarding, and basic table-link `gx` metadata.
- Inline keeps the Source buffer identity and restores wrap/conceal options.
- Runtime view, auto-preview, viewport, and refresh state is buffer-local.
- The pure-Lua scanner handles fences, top-level block boundaries, missing
  cells, escaped pipes, and arbitrary-length matching backtick runs in one pass.
- Renderer widths use Neovim display width and continuous border highlight
  ranges.
- Theme setup supports custom presets, colorscheme replay, explicit
  backgrounds, and background-transparent linked content highlights.
- Code-wrapped link labels do not shift Inline table separators.
- Neovim 0.10.4 and stable are tested in CI.

These are regression baselines, not unfinished roadmap items.

## Delivery Order

The order below is intentional:

1. Repair immediate Reader compatibility without expanding the public surface.
2. Make mode identity, mappings, navigation, and lifecycle coherent.
3. Formalize parser/source metadata and broaden conformance.
4. Build richer table interaction and optional editing on exact mappings.
5. Freeze and harden the public contract for 1.0.

## v0.2.4 — Reader Compatibility Patch (Delivered In v0.3.0)

### Goal

Remove the most disruptive Reader integration failures with low-risk changes
that fit the existing v0.2 API. This release does not introduce a general
mapping framework or promise arbitrary Source-plugin execution inside Reader.

### Work Package 0.2.4.1 — Safe Reader Link Fallback — Complete

User outcome:

- Reader `gx` opens a rendered table target when one is present and otherwise
  preserves the user's previous behavior.

Development work:

1. Reuse one tested mapping-invocation helper for Source and Reader.
2. Capture the effective fallback needed by Reader before installing its local
   `gx` mapping.
3. Support callback, string, expression, remap, and `replace_keycodes` cases.
4. Consume `gx` only after a valid rendered target is resolved.
5. Restore or discard captured mappings correctly on Reader wipe and repeated
   setup.

Acceptance criteria:

- A custom `gx` is called exactly once outside a rendered target.
- A rendered link opens exactly once and does not also invoke the fallback.
- Default setup leaves Source mappings unchanged.

### Work Package 0.2.4.2 — Native Buffer Exit Safety — Complete

User outcome:

- Leaving Reader through normal buffer/window commands does not strand Source
  state or produce save errors from the disposable projection.

Development work:

1. Add lifecycle tests for `:bnext`, `:bprevious`, `<C-^>`, window close, Reader
   wipe, modified Source, and `hidden` disabled.
2. Centralize Reader cleanup so explicit close and implicit buffer loss restore
   `bufhidden`, window options, and Reader state consistently.
3. Distinguish the Source modified flag from the disposable Reader modified
   mirror during navigation.
4. Avoid reopening Reader during the same transition that is leaving it.

Acceptance criteria:

- Native buffer navigation completes without a stale Reader state entry.
- Unsaved Source text remains loaded and modified.
- No Reader scratch buffer appears as a normal listed buffer.

### Work Package 0.2.4.3 — Document The Current Contract — Complete

1. Add a concise mode-choice guide to README and Vim help.
2. Document that `gf`, custom Reader passthrough, and third-party buffer-cycle
  integration become v0.3 work rather than claiming current support.
3. Expand the release-only manual matrix with custom `gx`, native buffer
  cycling, Bufferline/Telescope exit, and modified Source cases.

### Work Package 0.2.4.4 — Narrow-Pane Display-Width Safety — Complete

User outcome:

- A table remains geometrically stable in a narrow tmux pane even when a cell
  contains an unbroken inline-code token such as
  `` `tracepoint:sched:sched_process_exec` ``.

Development work:

1. Keep a code span as one styled item when its display width fits the target
   column.
2. Expand only oversized code items into display-width-aware character pieces,
   preferring punctuation boundaries where possible.
3. Re-evaluate the remaining tail after a preferred break so a wide CJK
   character or closing punctuation cannot push a cell past its column.
4. Exercise the shared renderer through both narrow Reader and Inline manual
   checks; do not duplicate mode-specific width algorithms.

Acceptance criteria:

- Every rendered line is no wider than the computed table width whenever the
  content can be represented within the configured column widths.
- Split code pieces retain `MarkdownTableWrapCode` styling and concatenate to
  the original display text.
- Reader and Inline use the same wrapped line objects and keep all vertical
  borders aligned in a 60-column test window containing CJK text and long code.

### v0.2.4 Release Gate

- The complete existing suite and new Reader regression tests pass on Neovim
  0.10.4 and stable.
- Narrow-window wrapping tests cover CJK punctuation and oversized inline-code
  tokens, with no rendered line exceeding the computed table width.
- No new default mapping is added.
- No existing setup option changes meaning.
- README, help, test documentation, CHANGELOG, and help tags agree.

## v0.3 — Transparent Modes And Neovim Integration — Complete

### Goal

Make Source, Inline, and Reader feel like views of one document instead of
separate interaction environments. v0.3 prioritizes daily navigation,
customization, lifecycle, and discoverability before broader parser features.

### Work Package 0.3.1 — Active Context And State Ownership — Complete

User outcome:

- Commands and integrations can always determine the real Source behind the
  current view.

Development work:

1. Add an internal active-context object containing mode, Source buffer/path,
   view buffer, window, cursor mapping, current table/cell/link metadata, and
   effective configuration.
2. Separate Source preferences, Inline window state, Reader session state, and
   Float state explicitly.
3. Add documented `get_state(bufnr?)` and Source-resolution APIs without
   exposing mutable internal tables.
4. Emit `User` events for Reader enter/leave, view changes, and completed
   rendering, including safe Source identifiers in event data.
5. Keep existing `get_buffer_config()` and `get_preview_mode()` behavior for the
   complete v0.3 line.

Acceptance criteria:

- The same Source opened in two windows returns two view contexts without
  sharing window geometry.
- Every public action resolves Reader back to its Source.
- Invalid/deleted Source state fails with one actionable message and cleans up.

### Work Package 0.3.2 — Mode-Agnostic Actions And Mapping Surface — Complete

User outcome:

- Users can keep their preferred keys and bind the same plugin action in any
  mode.

Development work:

1. Add an action router for view changes, Source editing, link/file opening,
   refresh, scrolling, and buffer transitions.
2. Provide documented `<Plug>` mappings for each stable action.
3. Make Reader and Float mappings individually configurable or disableable.
4. Support explicitly configured Source-mapping passthrough with a declared
   policy: execute in view, resolve in Source context, or leave then delegate.
5. Keep current commands as compatibility entry points while documenting a
   small recommended action set.
6. Add LuaLS annotations for configuration, action context, and callback return
   values.

Acceptance criteria:

- The documented Reader mapping disable switch creates no Reader-local user
  mappings.
- Existing global and buffer-local mappings survive setup/open/close cycles.
- A custom `H`/`L`, `gf`, or `gx` can be integrated without patching plugin
  internals.
- No default mapping overwrites unrelated behavior.

### Work Package 0.3.3 — Source-Aware Link And File Navigation — Complete

User outcome:

- Markdown links behave naturally from Reader as well as Source.

Development work:

1. Introduce a target model for external URI, relative file, absolute file,
   same-document anchor, file anchor, wiki link, image, and unresolved target.
2. Resolve relative targets from the Source directory.
3. Add mode-agnostic actions corresponding to `gf`, `gF`, `gx`, split, and tab
   opening without binding every native key by default.
4. Open file targets in Neovim and external URIs through `vim.ui.open` or a
   validated callback.
5. Resolve links in rendered tables and ordinary mirrored Markdown lines.
6. Offer a deterministic selector when a rendered cell contains multiple
   targets.
7. Preserve target metadata through wrapping and link icons.

Acceptance criteria:

- `[overview](curriculum/week-01/overview.md)` opens relative to Source from
  Source, Inline, and Reader.
- URL targets never become shell-interpolated commands.
- A missing file or unresolved anchor reports the resolved target and does not
  destroy the current view.
- User resolver callbacks can choose edit, split, tab, external open, or no-op.

### Work Package 0.3.4 — Buffer, Window, Tab, And Plugin Navigation — Complete

User outcome:

- Reader no longer blocks normal document switching workflows.

Development work:

1. Add leave-then-delegate actions for previous/next/alternate buffer, explicit
   buffer selection, splits, and tabs.
2. Preserve Source jumplist and alternate-buffer semantics where Neovim permits
   it; never add the scratch Reader as a user-visible history destination.
3. Handle Reader loss through external `:buffer`, Telescope, Harpoon,
   Bufferline, window close, and tab close without stale state.
4. Refresh Reader when its Source changes in another visible window.
5. Support one Source in multiple windows with independent Reader widths and
   cursors.
6. Define session restore behavior: restore Source first, then optionally
   restore the selected view after setup.

Acceptance criteria:

- Native `:bnext`, `:bprevious`, and `<C-^>` pass automated tests.
- Representative custom `H`/`L`, Bufferline, and Telescope transitions pass the
  manual matrix.
- Closing one Reader window does not alter another window's view of the same
  Source.
- No transition loses unsaved Source changes.

### Work Package 0.3.5 — Discoverability And Reduced Cognitive Load — Complete

User outcome:

- A user can understand the active view and common actions without reading the
  implementation-oriented configuration reference.

Development work:

1. Add `:MarkdownTableInspect` with active mode, Source path, Reader/view
   identity, table range, width budget, cache state, and effective options.
2. Add `:MarkdownTableHelp` with a compact Reader overlay showing configured
   keys and how to return to Source.
3. Expose a small statusline function returning Source/Inline/Reader and table
   position information.
4. Reorganize README around four tasks: read, edit, inspect, and troubleshoot.
5. Keep the full command reference but recommend no more than five common
   actions.
6. Expand `:checkhealth markdown-table-wrap` with Source-context, resolver,
   mapping, theme, and renderer-coexistence checks.

Acceptance criteria:

- Reader always has a discoverable exit/edit path even when default mappings
  are disabled.
- Inspection output is sufficient for a bug report without custom Lua.
- Documentation explains what copying and navigation mean in every mode.

### v0.3 Test Gate

- Test the complete transition matrix across Source, Inline, Reader, and Float.
- Test mapping callbacks, strings, expressions, remaps, `replace_keycodes`,
  disabled maps, and repeated setup.
- Test relative/absolute files, URLs, anchors, wiki links, missing targets, and
  multiple targets.
- Test two Source buffers, two windows, the same Source in two windows, tabs,
  modified/anonymous/deleted Source, and `hidden` disabled.
- Test Native buffer commands automatically and representative Bufferline,
  Telescope, and Harpoon workflows manually without adding dependencies.
- Test Reader search/yank, Source edit round trips, save forwarding, and exact
  cleanup on every exit path.
- Run Neovim 0.10.4/stable CI and the macOS/Linux terminal manual matrix.

### v0.3 Completion Criteria

- Source, Inline, and Reader expose one coherent action and context model.
- File/link navigation is Source-relative and mode-independent.
- User mappings are preserved, configurable, and testable.
- Reader does not appear as a duplicate normal buffer or break common buffer
  navigation.
- Multi-window Source/Reader state is isolated.
- Help, inspection, health, events, and Lua APIs are documented.

### v0.3 Compatibility

- Existing v0.2 setup remains valid.
- `preview_mode`, `reader.auto_open`, and `map_gx` retain their existing meaning.
- New mapping and resolver behavior is additive or guarded by explicit options.
- Deprecated names, if unavoidable, remain aliases for the full v0.3 line and
  warn once per session with a replacement example.
- Reader remains the stable default for buffers containing tables; changing
  that default requires separate user feedback and migration evidence.

## v0.4 — Exact Metadata, GFM Correctness, And Performance

### Goal

Formalize the table and inline-Markdown models after the interaction contract is
stable. Improve correctness and observability without reopening mode semantics.

### Work Package 0.4.1 — Source-Spanned Table Model

1. Define Lua-annotated table, row, cell, delimiter, alignment, and source-span
   structures that can be produced without a live Neovim buffer.
2. Preserve row/column identity and byte ranges through normalization of
   missing/excess cells.
3. Preserve rendered-to-source metadata through width allocation and wrapping.
4. Keep a thin buffer adapter around the pure line-array parser.

Acceptance criteria:

- Every rendered cell segment can identify its Source table, row, column, and
  best available source range.
- Mapping survives resize, refresh, missing cells, and wrapped rows.

### Work Package 0.4.2 — Inline-Markdown Token Contract

1. Replace pattern-only display parsing with tokens that preserve source spans,
   rendered spans, kind, target metadata, and nesting.
2. Support arbitrary-length code spans throughout parsing and display.
3. Add balanced-parenthesis destinations, reference links, autolinks, nested
   emphasis/strikethrough, images, wiki links, and hard breaks incrementally.
4. Keep unsupported constructs visible and safe rather than partially
   concealing them.

Acceptance criteria:

- Wrapping never loses link/source metadata.
- Concealed delimiters never affect display-width allocation.
- Multiple links in one cell retain independent target ranges.

### Work Package 0.4.3 — GFM Conformance Corpus

1. Import attributed minimal fixtures for the official GFM table extension.
2. Classify each fixture as supported, deliberately unsupported, or invalid.
3. Add top-level fences, headings, definitions, HTML blocks, escaped pipes,
   missing/excess cells, and pipe-like prose boundaries.
4. Add container-prefix support for blockquotes/lists only after source spans
   are unambiguous.
5. Preserve the single-pass large invalid-pipe baseline.

Acceptance criteria:

- Every documented parser rule has a named fixture.
- Parser failures never conceal lines belonging to the next Markdown block.
- Unsupported nested/container cases fail visibly and locally.

### Work Package 0.4.4 — Optional Discovery Backend

1. Define one interface that returns candidate table ranges.
2. Keep the pure-Lua scanner as the guaranteed fallback.
3. Add optional Tree-sitter discovery only if measurements or conformance cases
   show a meaningful benefit.
4. Normalize all backends into the same source-spanned model.
5. Support `auto`, `lua`, and explicit `treesitter` diagnostics; `auto` falls
   back silently.

Acceptance criteria:

- Missing, outdated, or broken parsers never prevent a Markdown buffer opening.
- Backends return identical ranges for their shared supported corpus.
- Backend choice and fallback reason are inspectable.

### Work Package 0.4.5 — Caching And Resource Budgets

1. Cache discovery, parsing, display tokens, and layout independently using
   Source changedtick and relevant window/config signatures.
2. Avoid rebuilding document-wide Reader content for cursor-only changes.
3. Measure documents with ordinary prose, invalid pipe candidates, many small
   tables, one large table, and many semantic spans.
4. Verify wipe/close releases caches, extmarks, timers, and Reader sessions.

### v0.4 Completion Criteria

- The public mode/action contract from v0.3 remains unchanged.
- Supported GFM fixtures have exact table/source metadata.
- The Lua backend remains available and has no known quadratic scan.
- Optional Tree-sitter use is measurable, diagnosable, and never required.
- Large-document parsing and Reader refresh have documented reference budgets.

## v0.5 — Table Workbench

### Goal

Build richer reading and explicit editing features on the exact metadata from
v0.4 without turning automatic rendering into a source formatter.

### Work Package 0.5.1 — Precise Cell Interaction

1. Return Reader edit commands to the exact Source cell/text range.
2. Add optional current-cell highlighting in Reader and Inline.
3. Add contextual next/previous cell and row actions with safe fallback.
4. Preserve marks/jumplist behavior when crossing Reader and Source.
5. Add a focused long-cell detail popup.

### Work Package 0.5.2 — Copy And Export

1. Copy the current displayed cell.
2. Copy one rendered table.
3. Export selected/current tables as TSV and CSV with correct escaping.
4. Keep Source copy, rendered copy, and export commands explicitly distinct.

### Work Package 0.5.3 — Wide-Table Layout Policies

1. Keep current wrap-and-fit behavior as the compatibility default.
2. Add an optional horizontal column viewport with clear hidden-column markers.
3. Add per-column minimum, maximum, fixed width, weight, and priority rules.
4. Keep the active cell visible across resize and navigation.
5. Define deterministic behavior when constraints cannot all be satisfied.

### Work Package 0.5.4 — Reader Ergonomics

1. Add optional sticky table headers without changing copied text.
2. Show table/row/column position through the statusline API.
3. Improve help and target selection for multiple links.
4. Verify Reader behavior in narrow splits and multiple UI clients.

### Work Package 0.5.5 — Optional Source Editing Companion

All mutations remain explicit and operate only on Source:

1. Format the current table.
2. Add, delete, and move rows or columns.
3. Toggle column alignment.
4. Edit a long cell in a focused popup and write it to the exact source range.
5. Make every operation one normal undo step.
6. Reject unsafe rewrites with a clear message and no partial change.

### v0.5 Completion Criteria

- Every interaction targets a stable table/cell/source identity.
- Layout policies are deterministic and per-window.
- Copy/export semantics are explicit and tested with Unicode and delimiters.
- Editing is optional, undoable, and never triggered by rendering.
- v0.3 integrations and v0.4 parser contracts remain compatible.

## v1.0 — Stable Public Contract

### Goal

Freeze a documented, supportable, performance-bounded contract for the 1.x
series.

### Work Package 1.0.1 — Public Surface Audit

1. Inventory every option, command, `<Plug>` mapping, action, Lua function,
   callback, `User` event, highlight group, and public model field.
2. Mark internal modules and experimental fields clearly.
3. Publish semantic-versioning and deprecation policies.
4. Provide migration examples for every changed name or behavior since v0.2.

### Work Package 1.0.2 — Compatibility And Accessibility

1. Test the minimum supported Neovim and the two newest stable releases.
2. Define behavior for no Tree-sitter, no Nerd Font, ASCII borders, light/dark
   themes, high contrast, narrow windows, and multiple UI clients.
3. Verify the documented coexistence contract with `render-markdown.nvim`.
4. Decide Neovim 0.10 support in a prior release, never silently in 1.0.

### Work Package 1.0.3 — Failure And Resource Hardening

1. Validate every nested option and callback result.
2. Keep parser/theme/resolver failures local to the affected view/table.
3. Test anonymous, readonly, modified, unloaded, renamed, and deleted Source.
4. Test repeated setup, lazy loading, buffer wipe, session restore, and plugin
   reload.
5. Enforce documented parser/layout/refresh resource budgets.

### Work Package 1.0.4 — Documentation And Release Candidate

1. Provide a short installation path, mode-choice guide, common-workflow guide,
   complete reference, troubleshooting guide, and migration guide.
2. Add maintained media for Reader, Inline, Float, link navigation, exact-cell
   interaction, and wide-table layout.
3. Publish at least one release candidate and freeze features during its
   compatibility period.

### v1.0 Completion Criteria

- Source, Inline, Reader, and Float contracts are documented and tested.
- No known data-loss, mapping takeover, stale state, cross-window state leak,
  or quadratic parser defect remains.
- Public APIs/events/mappings have compatibility tests and examples.
- Performance and compatibility matrices are published.
- A clean tagged installation passes health, tests, help, and manual workflows.

## Deferred Or Deliberately Out Of Scope

The following do not move ahead of the milestones above without new evidence:

- Becoming a complete Markdown renderer.
- Requiring Tree-sitter for normal operation.
- Adding plugin-specific hard dependencies solely for Bufferline/Telescope/etc.
- Automatically rewriting or formatting Source during render/refresh.
- Listing Reader as a normal buffer and exposing duplicate document identities.
- Replacing proven rendering code as part of an interaction-only feature.
- Adding many default mappings to imitate a distribution's key scheme.
- Remote content previews, link fetching, or execution of embedded content.

## Work Package Procedure

For every package:

1. Restate the user outcome and acceptance criteria.
2. Record failing user-journey tests or baseline measurements first.
3. Add low-level tests, then mode/action/lifecycle tests, then manual checks.
4. Implement the smallest coherent architecture change.
5. Run the complete suite, not only focused tests.
6. Update README, Vim help, help tags, tests documentation, CHANGELOG, and this
   roadmap in the same change.
7. Record compatibility or migration effects explicitly.
8. Leave the repository releasable before beginning the next package.

## Release Checklist Shared By All Milestones

From a clean working tree:

```sh
stylua --check .
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

Then:

- Regenerate `doc/tags` with `:helptags doc` and review the diff.
- Run `git diff --check`.
- Validate README, PUBLISHING, ROADMAP, help links, and repository asset paths.
- Run `:checkhealth markdown-table-wrap` and open
  `:help markdown-table-wrap`.
- Test `markdown`, `quarto`, and `rmd` lazy loading.
- Run the mode-transition and Source-identity manual matrix.
- Test custom mappings, links/files, native buffer navigation, Bufferline or an
  equivalent buffer UI, Telescope or an equivalent picker, and modified Source.
- Test narrow/wide windows, CJK/emoji, code spans, links, custom highlights,
  wrap/conceal, and colorscheme changes.
- Verify Source text remains unchanged after every automatic rendering path.
- Confirm version metadata, CHANGELOG, annotated tag, and GitHub release title
  match.
- Tag only a green `master` commit and never move a published tag.

For the exact publishing commands and current release assets, see
[PUBLISHING.md](PUBLISHING.md). For the current automated/manual coverage map,
see [tests/README.md](tests/README.md).
