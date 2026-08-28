# Architecture

This document explains how `markdown-table-wrap.nvim` works internally. Public
configuration and commands belong in `README.md` and Vim help; active work and
release readiness belong in `CODEX_HANDOFF.md`.

## System Boundary

The plugin recognizes GFM-style pipe tables in supported Markdown buffers and
presents wrapped, width-aware rendered views. It is not a complete Markdown
renderer and does not format Source. The original Markdown buffer is the only
canonical document; every rendered representation is derived and disposable.

The four modes are views with different ownership:

| Mode | Buffer ownership | Rendering mechanism | Intended role |
| --- | --- | --- | --- |
| Source | User's real buffer | None | Canonical editing and native Neovim behavior |
| Inline | Source buffer | Extmarks and virtual lines/text | Read near the original lines without changing buffers |
| Reader | Unlisted `acwrite` scratch buffer | Real rendered lines plus authoritative overlay extmarks | Full-document reading, search, selection, yank, and Source-aware actions |
| Float | Disposable scratch buffer/window | Rendered table under the cursor | Short focused preview |

## Main Data Flow

```text
Source buffer
  │ changedtick + lines
  ▼
discovery.lua ── candidate ranges ──► parser.lua
                                        │
                         markdown.lua ◄──┤ cell inline tokens
                                        │
                     source-spanned table model
                                        │
                                        ▼
                         render.lua + wrap.lua + width.lua
                                        │
                   rendered lines + semantic chunks + Source mapping
                         ┌──────────────┼──────────────┐
                         ▼              ▼              ▼
                      inline.lua     reader.lua     Float in render.lua
                         └──────────────┬──────────────┘
                                        ▼
                        context.lua → actions.lua → links.lua
```

`cache.lua` sits beside discovery, parsing, inline-token parsing, and layout.
It accelerates repeated derivation but never becomes the authority for Source
text or user intent.

## Module Responsibilities

| Module | Responsibility |
| --- | --- |
| `init.lua` | Defaults, configuration validation, per-buffer overrides, commands, `<Plug>` mappings, autocommands, scheduling, and high-level view selection |
| `discovery.lua` | Finds candidate table ranges through deterministic Lua or explicit optional Tree-sitter discovery; records backend/fallback diagnostics |
| `parser.lua` | Validates table structure and builds exact table/row/cell/delimiter Source models from a live buffer or a pure line array |
| `markdown.lua` | Tokenizes supported inline Markdown inside cells and retains Source/render coordinates and target metadata |
| `wrap.lua` | Wraps styled cell content at display-width-safe character boundaries while retaining token and Source metadata |
| `width.lua` | Unicode display-width measurement, padding, alignment, and repeated border characters |
| `render.lua` | Allocates column widths and produces rendered line objects, borders, semantic chunks, cell segments, and Float views |
| `inline.lua` | Owns Source-buffer extmarks, inline replace/insert presentation, window wrap restoration, and optional viewport offsets |
| `reader.lua` | Builds full-document Reader buffers, maps Reader lines/cells to Source, protects rendered tables from secondary Markdown parsing, and owns Reader lifecycle |
| `cell_ops.lua` | Resolves the logical Reader cell, performs exact Source-span yank/mutation operations, enters Source Insert for changes, and installs configurable cell mappings/fallbacks |
| `export.lua` | Resolves Source-backed cell/table identity, copies semantic rendered values, and serializes selected tables as TSV/CSV without Source mutation |
| `table_edit.lua` | Performs explicit, validated Source table rewrites (format, row/column structure, alignment) and one-cell popup edits; never participates in automatic rendering |
| `context.lua` | Resolves any view to one mode-independent Source/table/cell/window context |
| `actions.lua` | Dispatches mode-independent commands and safely leaves disposable views before buffer/window operations |
| `links.lua` | Extracts/classifies targets, resolves paths relative to Source, opens targets, and supports custom resolution |
| `mappings.lua` | Captures, invokes, and restores user mappings without losing callback/expr/remap/keycode behavior |
| `cache.lua` | Owns changedtick/signature-keyed discovery, parse, and layout entries and global counters |
| `events.lua` | Emits normalized `User` events without exposing mutable internal tables |
| `inspect.lua` / `health.lua` | Report resolved context, mappings, backend, caches, modules, renderer coexistence, and configuration health |
| `theme.lua` | Defines and applies highlight presets and overrides |
| `nav.lua` | Source-table cell movement and Source link fallback helpers |
| `types.lua` | LuaLS annotations for the public context, target, configuration, and source-spanned model contracts |

## Source-Spanned Model

`parser.parse_lines(lines, opts?)` is the pure adapter. `parser.parse_all(bufnr,
opts?)` adds live-buffer identity, changedtick, discovery backend, and cache use.
Models use 1-based line numbers and 0-based byte columns with exclusive end
columns, matching Neovim extmark conventions.

A table owns:

- stable identity and an exact Source span;
- header and body row metadata;
- a delimiter model and column alignments;
- normalized cells with `present=false` for missing cells;
- separately retained overflow cells for excess Source cells.

Every present cell retains raw text, rendered display text, inline tokens,
semantic spans, table/row/column identity, and its Source span. Wrapping copies
that identity into every rendered cell segment. This metadata is what allows
Reader cursor positions and view-independent actions to return to Source.

## Discovery And Parsing

Normal `discovery.backend = "auto"` intentionally chooses the Lua scanner. The
scanner skips fenced code and returns candidate ranges; `parser.lua` remains
responsible for structural validation and Markdown block boundaries. Explicit
`"treesitter"` discovery may return pipe-table nodes, but missing, incompatible,
or unhelpful parsers fall back to Lua. Both paths feed the same parser and model.

Inline Markdown is deliberately scoped to table-cell display semantics. The
tokenizer supports the documented code/link/emphasis/image/wiki/autolink forms,
but unmatched or unsupported syntax stays literal rather than being partially
concealed.

## Rendering And Geometry

Column geometry is computed in display cells, not bytes. Natural widths are
clamped by configured minimum/maximum values and then reduced to the available
window text width when `fit_to_window` is enabled. `wrap.lua` splits semantic
content without splitting a multibyte character and propagates token metadata
to each segment.

`render.render_table()` returns real lines and parallel line objects. A line
object carries semantic highlight chunks and rendered cell ranges. Reader uses
real lines so search, selection, and yank behave normally, then places one
authoritative conceal/overlay extmark on each rendered table line. The overlay
prevents the Reader's Markdown filetype or another renderer from reparsing
underscores and angle brackets and visually moving borders.

## Reader Cell Operations And Selection

Reader line objects carry the same table/row/column identity on every wrapped
segment of a cell. `reader.cell_at_cursor()` gathers those segments into one
logical range and returns the exact Source span. `cell_ops.lua` is the only
mutation boundary for the Reader cell mappings:

```text
Reader cursor → logical rendered cell → Source span
       │                  │                 │
       ├─ yic ────────────┴─ read raw text → registers
       ├─ vic ─────────────── select rendered segments (Visual overlay)
       ├─ dic/cip ─────────── nvim_buf_set_text(Source span) → refresh Reader
       └─ cic/c ───────────── set empty Source span → close Reader → Source Insert
```

`yic` copies the source slice, not the displayed label. `dic`, `cic`, and
`cip` replace only the cell's one-line Source span, leaving neighboring cells
and delimiters untouched. Newlines from a register are flattened to spaces and
multi-line or synthetic missing cells are rejected rather than causing an
implicit row rewrite. A changedtick check refreshes a stale Reader projection
before resolving a cell.

`vic` enters native blockwise Visual mode over the rendered cell's first and
last real lines. Blockwise selection is deliberate: charwise Visual would
include every column on intermediate wrapped lines. Native `v`, `V`, and block
Visual remain unchanged; `reader.lua` mirrors
their active range into a higher-priority `Visual` virtual-text overlay because
the base table overlay otherwise hides the terminal's normal selection
feedback. The overlay namespace is cleared on movement out of Visual, Reader
close/abandon, and buffer cleanup. It affects appearance only and never changes
the register contents or Source selection semantics. In normal mode it adds no
per-cell extmarks; only the currently selected Reader lines are overlaid, so
large Readers retain the v0.4 one-authoritative-extmark-per-rendered-line
baseline.

## Rendered Copy And Export

Copy and export intentionally have different semantics from `yic` and native
Source yank:

```text
Source/Reader context → stable table/cell identity
  ├─ rendered cell → semantic display text (no Markdown delimiters/icons)
  ├─ rendered table → current layout lines, including borders
  └─ TSV/CSV export → parsed fields with format-specific escaping
```

`export.lua` always resolves the canonical Source buffer first. Reader and
Float may reuse their already-built rendered table, while Source and Inline
render on demand with the active window configuration. Clipboard writes update
the unnamed/yank registers (and `+` when enabled); no export path edits Source.
TSV uses C-style escapes for control characters, and CSV doubles embedded
quotes and quotes fields containing delimiters or line breaks.

## Source Editing Companion

`table_edit.lua` is the explicit mutation boundary for structural table
operations. It is deliberately separate from `render.lua`, `reader.lua`, and
automatic refresh scheduling: rendering can only derive views, while a user
command or a named action must opt into a Source rewrite.

The pipeline is:

```text
current view → context/source resolution → parse current table
      │                  │                         │
      │                  │                         ├─ reject excess cells
      │                  │                         ├─ build normalized rows
      │                  │                         └─ preserve alignments
      │                  └─ leave Reader/Float (if needed)
      └─ canonical Source replacement → one undo step → normal refresh path
```

Formatting and row/column operations replace the table's complete physical
range in one `nvim_buf_set_lines()` call. This makes each command one normal
undo unit and avoids a partially rewritten delimiter or row. The formatter
uses display width for padding and emits parser-valid delimiter cells. Tables
with excess Source cells are refused before any mutation; deleting the final
column is also refused. Missing normalized cells remain empty and are never
silently reconstructed from neighboring text.

`MarkdownTableEditCell` uses a nofile scratch float only as a focused editor for
one present, one-line Source span. `<C-s>` commits the popup text with one
`nvim_buf_set_text()` range replacement; `Esc`/`q` discards it. The popup is not
an alternate document buffer, has no save path, and is always disposable. A
Reader or Float is closed before a commit so Neovim's normal Source undo,
modified flag, mappings, and integrations remain authoritative.

## State Model

There are several intentionally separate state layers:

- `M.config`: validated global configuration produced by `setup()`.
- `M.state`: high-level Float ownership plus per-Source mode, auto-preview,
  pause, viewport, refresh token, signature, and mapping overrides.
- `reader.lua`: Reader-buffer states and shared Source ownership. One Source may
  have multiple width-specific Reader windows; each state records the Source
  changedtick used to build its projection so cell actions can reject stale
  metadata safely. Logical cell segments and header lines are indexed during
  build, so cell actions and optional sticky-header updates do not scan the
  complete rendered document on every cursor move.
- `inline.lua`: active Source buffers/tables/configs, per-window saved wrap
  options, and viewport offsets.
- `cache.lua` / `discovery.lua`: derived data and diagnostics keyed by Source.

`paused` represents persistent user intent, not visibility:

```text
automatic Source ──open policy──► Reader
      ▲                              │
      │ native buffer/window leave  │
      └──────── Source unpaused ◄────┘

Reader ──explicit close/edit/disable──► Source paused
Source paused ──explicit preview/enable──► rendered view, pause cleared
```

Native Reader `BufHidden` cleanup calls `reader.abandon()` and deletes only the
disposable view. It must not set the Source pause flag. When the Source next
enters a window, the normal debounced auto-preview policy runs again.

## Lifecycle And Scheduling

`setup()` validates configuration, clears derived caches, invalidates scheduled
refresh epochs, recreates one augroup, registers public commands/mappings,
applies the theme, and reconfigures surviving Reader views.

Relevant lifecycle events are debounced per Source buffer. Each scheduled
refresh captures the Source's token and the global setup epoch; stale callbacks
exit without touching state. Text changes refresh visible dependent Readers or
recompute Inline. Resizes invalidate layout signatures. Buffer wipe releases
Reader/Inline state, caches, discovery status, mappings, pause state, viewport
state, and scheduled tokens. Window close restores Inline-owned options.

Reader open snapshots Source cursor/window options, sets Source `bufhidden` to
`hide` while dependent Readers exist, builds the complete derived document,
then switches the window to an unlisted protected scratch buffer. Explicit close
maps the Reader cursor back to Source, restores options and ownership, and
deletes the scratch buffer. `:write` in Reader delegates to the Source through
`BufWriteCmd`; the Reader never owns edits.

Cell changes are the exception to the general “Reader is protected” rule only
in terms of their entry point: the Reader remains non-modifiable, while
`cell_ops.lua` applies a guarded `nvim_buf_set_text()` directly to Source and
then rebuilds the disposable projection. `cic`/`c` deliberately close the
Reader before `startinsert` so Neovim's Insert mode, undo history, and buffer
local plugins operate on the real Source buffer.

## Context, Actions, Links, And Mappings

All public interaction begins by resolving a context. The context identifies
the view, canonical Source, mapped Source cursor, table/cell metadata, window,
cache status, discovery backend, and effective configuration. Actions use this
context instead of branching on buffer names.

File targets resolve relative to the Source path even when invoked from Reader
or Float. Actions that change buffers first dispose of the temporary view and
restore Source ownership. Reader passthrough mappings may run a named plugin
action, run a captured mapping in Source context, or leave Reader before
invocation. Captured mappings must be restored exactly.

## Cache And Invalidation

Buffer-owned cache stages are independent:

- discovery: backend plus Source changedtick;
- parse: backend/cache policy plus Source changedtick;
- layout: table identity, Source changedtick, window text width, geometry
  options, border choices, row separators, and link rendering configuration;
- inline-token cache: bounded process-local cache keyed by input/reference
  signature.

Cache values are copied at the boundary so callers cannot mutate stored model
state. Source wipe and repeated `setup()` clear owned entries. New options that
affect any derived output must be added to the corresponding signature.

## Scaling Constraints

Discovery and parsing are intended to be linear in Source size. Full Reader
cost is instead proportional to rendered output: a 4,000-line Source table may
become roughly 20,000 Reader lines after wrapping. Reader currently
materializes every line and line-object before opening and refreshes the whole
scratch buffer. One authoritative overlay extmark is installed per rendered
table line.

Optional sticky headers use only the Reader window's `winbar`; they never add
buffer lines or overlay extmarks. The previous window `winbar` is part of the
Reader transition snapshot and is restored when the cursor leaves a table or
the Reader closes.

Once built, `gg` and `G` are native buffer movements and do not trigger table
parsing. Initial build, full refresh, terminal redraw, and third-party Markdown
processing can still be perceptible for very large rendered documents. The
reference measurements and opt-in stress command live in
`docs/performance.md`; future viewport/lazy materialization must preserve exact
Source mapping, search/yank semantics, and renderer isolation.

## Extension Rules

- Add new table syntax in `parser.lua` and the classified fixture corpus before
  teaching a view to special-case it.
- Add inline syntax in `markdown.lua`, then verify wrapping and target metadata.
- Add a cross-mode user operation to `actions.lua` and expose it through
  context-aware commands or `<Plug>` mappings rather than hard-coding
  mode-specific keys. Reader-only Source-span cell operations may stay in
  `cell_ops.lua` while their semantics are experimental, but must still use
  the shared context/source-span model and configurable mapping boundary.
- Add view-specific state to the owning view module; add only orchestration and
  per-Source policy to `init.lua`.
- Add cache signatures whenever output depends on a new option.
- Preserve exact Source identity and include lifecycle cleanup tests for every
  new disposable buffer, window, timer, namespace, or cache.
