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
```

Read [tests/README.md](tests/README.md) before adding a feature: it maps the
test layers and lists terminal-specific release checks that headless CI cannot
cover.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing module
ownership, mode state, Source mapping, lifecycle, caches, or rendering data
flow.

## Pull Requests

- Keep changes focused on Markdown table rendering unless the issue explicitly asks for broader Markdown behavior.
- Add or update tests for parser, wrapping, rendering, theme, or inline extmark changes.
- Do not introduce external binary dependencies.
- Keep the source Markdown buffer read-only from the renderer's perspective.

## Useful Manual Checks

- Open a Markdown file with one short table and one very wide table.
- Verify source text is visible in Insert mode.
- Verify rendered tables return in Normal mode.
- Verify `render-markdown.nvim` table rendering is disabled when testing coexistence.
- Run `:checkhealth markdown-table-wrap`.
