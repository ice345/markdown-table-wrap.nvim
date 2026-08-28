# Performance Reference

v0.5 retains the v0.4 separation of table discovery, parsing/inline tokens, and
layout caches. The explicit Source editing companion does not run during
rendering and therefore does not change the read-only rendering cost model. A
Source buffer changedtick invalidates discovery and parse results; the layout
stage additionally includes the window text width and geometry-related options.
Closing or wiping the Source releases every buffer-owned cache entry.

Run the reference benchmark from the repository root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/benchmark.lua" \
  -c "qa!"
```

The benchmark covers ordinary prose, invalid pipe candidates, many small
tables, and a large table containing many semantic spans. These are reference
budgets rather than CI timing assertions because hosted runners and local
machines vary substantially:

| Scenario | Reference input | v0.4 budget on a current desktop |
| --- | ---: | ---: |
| Ordinary prose | 10,000 lines | below 100 ms |
| Invalid pipe candidates | 10,000 lines | below 250 ms |
| Many small tables | 500 tables / 2,000 lines | below 250 ms |
| Semantic-span stress | 1,000 body rows | below 500 ms |
| Unchanged live-buffer parse | cached changedtick | below 10 ms |

Regressions should be investigated when a scenario repeatedly exceeds its
budget by more than 25% on the same machine. Correctness tests still take
priority over timing: no cache may reuse results across changedticks, window
width signatures, or relevant layout configuration changes.

## Large Reader Stress

The default benchmark measures parser/model work. A full Reader has a different
cost model because one Source row may wrap into several real Reader lines. Run
the opt-in stress case with:

```sh
MARKDOWN_TABLE_WRAP_BENCH_READER=1 \
  nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/benchmark.lua" \
  -c "qa!"
```

At 110 columns, the fixture contains 4,002 Source lines and currently expands
to about 20,005 Reader lines. The Reader installs one authoritative
conceal/overlay extmark per rendered table line. On one Apple Silicon
development machine with Neovim 0.12.4, a representative run after that extmark
consolidation measured approximately:

| Operation | Reference result |
| --- | ---: |
| Cold Reader open | 1.4–1.5 s |
| Cached full Reader refresh | 0.30 s |
| 500 `gg`/`G` pairs | 42–47 ms total |
| Reader table extmarks | 20,005 |

These figures are diagnostic, not a zero-latency guarantee. Headless movement
does not measure terminal drawing, font shaping, syntax engines, or third-party
Markdown renderers. After the Reader exists, `gg` and `G` are native Neovim
buffer movements and do not rerun table parsing. Cold construction and full
refresh still materialize the complete rendered document, so very large tables
can produce a visible pause. A future lazy/viewport architecture must be judged
against this scenario without sacrificing search, selection, yank, exact
Source mapping, or renderer isolation.
