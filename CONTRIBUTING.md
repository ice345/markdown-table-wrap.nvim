# Contributing

Thanks for helping improve `markdown-table-wrap.nvim`.

## Development

Run the test suite from the plugin root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

Format Lua before opening a pull request:

```sh
stylua .
git diff --check
```

Run the benchmark when changing discovery, parsing, caching, layout, extmarks,
or Reader construction:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/benchmark.lua" \
  -c "qa!"
```

Read [tests/README.md](tests/README.md) before adding a feature: it maps the
test layers and lists terminal-specific release checks that headless CI cannot
cover.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing module
ownership, mode state, Source mapping, lifecycle, caches, or rendering data
flow.

## Maintenance And Compatibility

After 1.0, prioritize reproducible defects, compatibility changes, and concrete
reading/editing workflows. A stable plugin does not need new features or a
release on a fixed schedule. Maintainer use, supported Neovim upgrades, and
relevant performance checks can reveal work even when no issue has been filed.

For a proposed capability, describe the failing or missing workflow, why the
existing commands/APIs are insufficient, acceptance examples, and Source-safety
and maintenance costs. Keep speculative Markdown dialects, extra views, and
large rewrites out of unrelated fixes.

Preserve the documented 1.x contract in README and Vim help. Patch releases fix
contract defects; minor releases add compatible capabilities. Changes to public
APIs, defaults, mappings, or the supported baseline need compatibility review;
breaking changes require a major release and migration notes. Cover changed
contracts with behavioral regressions, not tests of private implementation.

## Pull Requests

- Keep changes focused on Markdown table rendering unless the issue explicitly
  asks for broader Markdown behavior.
- Add or update tests for parser, wrapping, rendering, theme, mappings,
  lifecycle, caching, or extmark changes.
- Do not introduce external binary dependencies.
- Keep the supported baseline at Neovim 0.10+.

## Design Invariants

- The Markdown Source buffer is canonical. Automatic rendering must never
  rewrite, normalize, or format it; Reader and Float buffers are disposable
  views and must not own user data.
- Resolve actions, links, paths, cursors, and status back to the same Source
  identity in Source, Inline, Reader, and Float modes.
- Preserve user mappings exactly. Buffer-local proxies must restore callback,
  expression, remap, and keycode behavior when detached.
- Measure layout in display cells. Neovim ranges and Source spans use 0-based
  byte columns with exclusive end columns.
- Unsupported Markdown stays visible and local. Optional Tree-sitter discovery
  must fall back safely to the deterministic Lua path.
- Cache keys must include every relevant Source changedtick, backend, window
  width, and layout/config value. Source wipeout must release all dependent
  caches, timers, extmarks, and views.
- Reader's authoritative table overlay prevents secondary Markdown renderers
  from moving visible borders. Changes to it require coexistence coverage for
  links, inline-code underscores, angle brackets, and third-party renderers.

Run the full suite on Neovim 0.10.4 and current stable when changing public
APIs, parsing, extmarks, mappings, lifecycle, or caching. Do not weaken a
correctness assertion to meet a machine-dependent timing target.

## Useful Manual Checks

- Open a Markdown file with one short table and one very wide table.
- Verify source text is visible in Insert mode.
- Verify rendered tables return in Normal mode.
- Verify `render-markdown.nvim` table rendering is disabled when testing coexistence.
- Run `:checkhealth markdown-table-wrap`.
