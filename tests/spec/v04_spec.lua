local h = require("tests.helpers")

h.test("v0.4 pure parser exposes exact row cell and delimiter source metadata", function()
  local parser = require("markdown-table-wrap.parser")
  local tables = parser.parse_lines({
    "| Name | Value |",
    "| :--- | ---: |",
    "| one | `two` | extra |",
    "| only |",
  })
  local model = tables[1]

  h.assert_true("pure line-array table parsed", model ~= nil)
  h.assert_eq("stable pure table identity", model.id, "1:4")
  h.assert_eq("table source starts at header", model.source_span.start_lnum, 1)
  h.assert_eq("delimiter model retains its row", model.delimiter.source_lnum, 2)
  h.assert_eq("delimiter cell retains table identity", model.delimiter.cells[1].table_id, model.id)
  h.assert_eq("body row identity", model.rows[1].row_index, 1)
  h.assert_eq("cell column identity", model.rows[1][2].column_index, 2)
  h.assert_eq("cell byte start", model.rows[1][2].source_span.start_col, 8)
  h.assert_eq("cell byte end", model.rows[1][2].source_span.end_col, 13)
  h.assert_eq("inline token has an absolute Source start", model.rows[1][2].tokens[1].source_start_col, 8)
  h.assert_eq("excess cells retain metadata", #model.rows[1].overflow_cells, 1)
  h.assert_eq("excess cell retains table identity", model.rows[1].overflow_cells[1].table_id, model.id)
  h.assert_false("missing normalized cell is marked synthetic", model.rows[2][2].present)
  h.assert_eq("missing cell has a zero-width Source range", model.rows[2][2].source_span.start_col, 8)
  h.assert_eq("missing cell range is stable", model.rows[2][2].source_span.end_col, 8)
end)

h.test("v0.4 rendered cell segments retain Source identity through wrapping and resize", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | `very_long_code_token_with_parts` |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local model = parser.parse_all(buf, { backend = "lua" })[1]
    local config = {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 12,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = false,
      link = {},
    }
    vim.api.nvim_win_set_width(0, 60)
    local narrow = render.render_table(model, config)
    vim.api.nvim_win_set_width(0, 90)
    local wide = render.render_table(model, config)

    local function verify(rendered)
      local segments = 0
      for _, line in ipairs(rendered.line_objects) do
        for _, cell in ipairs(line.cells or {}) do
          if cell.row_index == 1 and cell.column_index == 2 then
            segments = segments + 1
            h.assert_eq("rendered segment keeps table identity", cell.table_id, model.id)
            h.assert_eq("rendered segment keeps Source row", cell.source_span.start_lnum, 3)
            h.assert_true("rendered segment has an ordinal", cell.segment_index >= 1)
          end
        end
      end
      h.assert_true("wrapped model produces mapped cell segments", segments > 0)
    end
    verify(narrow)
    verify(wide)
  end)
end)

h.test("v0.4 inline tokens support balanced links references autolinks and nesting", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline(
    "[**bold**](docs/a_(b).md) [ref][guide] <https://example.com/a> ``code ` inner`` BPF_PROG_TYPE",
    { references = { guide = { target = "guide.md" } } }
  )
  local links = markdown.extract_links(parsed)
  local kinds = {}
  for _, token in ipairs(parsed.tokens) do
    kinds[token.kind] = true
    h.assert_true("token has Source coordinates", token.source_start_col ~= nil and token.source_end_col ~= nil)
    h.assert_true("token has rendered coordinates", token.render_start_col ~= nil and token.render_end_col ~= nil)
  end

  h.assert_eq("three independent targets", #links, 3)
  h.assert_eq("balanced destination preserved", links[1].target, "docs/a_(b).md")
  h.assert_eq("reference destination resolved", links[2].target, "guide.md")
  h.assert_eq("autolink destination preserved", links[3].target, "https://example.com/a")
  h.assert_true("nested bold token retained", kinds.bold)
  h.assert_true("nested token tree retains rendered coordinates", parsed.tokens[1].children[1].render_end_col > 0)
  h.assert_true("arbitrary backtick token retained", kinds.code)
  h.assert_true("intraword underscores remain literal", parsed.text:find("BPF_PROG_TYPE", 1, true) ~= nil)
  h.assert_eq(
    "nested tokens do not duplicate display text",
    markdown.apply_link_icons(markdown.parse_inline("**outer *inner* end**"), { link = {} }).text,
    "outer inner end"
  )
end)

h.test("v0.4 reference definitions resolve inside table cells", function()
  local parser = require("markdown-table-wrap.parser")
  local model = parser.parse_lines({
    "| Name | Target |",
    "| --- | --- |",
    "| docs | [guide][manual] and [shortcut] |",
    "",
    "[manual]: docs/manual_(v2).md",
    "[shortcut]: quick.md",
  })[1]
  local links = require("markdown-table-wrap.markdown").extract_links(model.rows[1][2])
  h.assert_eq("two reference links survive one cell", #links, 2)
  h.assert_eq("full reference target", links[1].target, "docs/manual_(v2).md")
  h.assert_eq("shortcut reference target", links[2].target, "quick.md")
  h.assert_true("reference target ranges stay independent", links[1].end_col <= links[2].start_col)
end)

h.test("v0.4 Source actions receive resolved reference-link metadata", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  h.with_buffer({
    "| Name | Target |",
    "| --- | --- |",
    "| docs | [guide][manual] |",
    "",
    "[manual]: docs/manual.md",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 10 })
    local context = require("markdown-table-wrap.context").resolve({ bufnr = buf })
    local targets = require("markdown-table-wrap.links").targets(context)
    h.assert_eq("Source reference link produces one target", #targets, 1)
    h.assert_eq("Source reference target is resolved", targets[1].raw, "docs/manual.md")
    h.assert_true("Source target uses absolute syntax coordinates", targets[1].start_col >= 9)
  end)
end)

h.test("v0.4 token-aware raw extraction does not duplicate wiki links or autolinks", function()
  local targets = require("markdown-table-wrap.links").extract(
    "[[notes]] <https://example.com/path> [label](https://example.com/other)",
    "/tmp/readme.md"
  )
  h.assert_eq("each visible target is returned once", #targets, 3)
  h.assert_eq("wiki target retains classification", targets[1].kind, "wiki")
  h.assert_eq("autolink target retains URL", targets[2].raw, "https://example.com/path")
end)

h.test("v0.4 GFM corpus classifies supported invalid and unsupported fixtures", function()
  local parser = require("markdown-table-wrap.parser")
  local corpus = require("tests.fixtures.gfm_tables")
  for _, fixture in ipairs(corpus.cases) do
    local tables = parser.parse_lines(fixture.lines)
    if fixture.classification == "supported" then
      h.assert_eq(fixture.id .. " parses once", #tables, 1)
      h.assert_eq(fixture.id .. " column count", #tables[1].header, fixture.columns)
      h.assert_eq(fixture.id .. " body row count", #tables[1].rows, fixture.rows)
    elseif fixture.classification == "boundary" then
      h.assert_eq(fixture.id .. " keeps the preceding table", #tables, 1)
      h.assert_eq(fixture.id .. " does not consume the next block", tables[1].end_lnum, fixture.end_lnum)
    else
      h.assert_eq(fixture.id .. " stays visible and unparsed", #tables, 0)
    end
  end
end)

h.test("v0.4 discovery backend is inspectable and explicit Tree-sitter fails safe", function()
  local discovery = require("markdown-table-wrap.discovery")
  local lines = { "| A | B |", "| --- | --- |", "| one | two |" }
  local lua_ranges, lua_status = discovery.discover(nil, lines, { backend = "lua" })
  h.assert_eq("Lua discovery finds shared corpus", #lua_ranges, 1)
  h.assert_eq("Lua discovery reports backend", lua_status.used, "lua")

  local ts_ranges, ts_status = discovery.discover(nil, lines, { backend = "treesitter" })
  h.assert_eq("missing live Tree-sitter context falls back", ts_status.used, "lua")
  h.assert_true("Tree-sitter fallback reason is inspectable", ts_status.fallback_reason ~= nil)
  h.assert_deep_eq("fallback ranges equal Lua ranges", ts_ranges, lua_ranges)

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local live_ranges = discovery.discover(buf, lines, { backend = "treesitter" })
    h.assert_eq("shared backend start range matches", live_ranges[1].start_lnum, lua_ranges[1].start_lnum)
    h.assert_eq("shared backend end range matches", live_ranges[1].end_lnum, lua_ranges[1].end_lnum)
    local parser = require("markdown-table-wrap.parser")
    local lua_model = parser.parse_all(buf, { backend = "lua", cache = false })[1]
    local ts_model = parser.parse_all(buf, { backend = "treesitter", cache = false })[1]
    h.assert_eq("shared backends normalize the same table", ts_model.id, lua_model.id)
    h.assert_deep_eq("shared backends normalize the same Source span", ts_model.source_span, lua_model.source_span)
    h.assert_eq("shared backends normalize the same cell", ts_model.rows[1][2].text, lua_model.rows[1][2].text)
  end)
end)

h.test("v0.4 parse and layout caches invalidate by changedtick and window signature", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local cache = require("markdown-table-wrap.cache")

  h.with_buffer({ "| A | B |", "| --- | --- |", "| one | two |" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    cache.clear_buffer(buf)
    local before = cache.inspect(buf)
    local first = parser.parse_all(buf, { backend = "lua" })
    parser.parse_all(buf, { backend = "lua" })
    local parsed = cache.inspect(buf)
    h.assert_true("second parse hits cache", parsed.hits > before.hits)
    h.assert_true("discovery cache is independently owned", vim.tbl_contains(parsed.stages, "discovery"))
    h.assert_true("parse cache is independently owned", vim.tbl_contains(parsed.stages, "parse"))

    local config = {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 20,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = false,
      link = {},
    }
    render.render_table(first[1], config)
    render.render_table(first[1], config)
    local laid_out = cache.inspect(buf)
    h.assert_true("second layout hits independent cache", laid_out.hits > parsed.hits)
    local has_layout = false
    for _, stage in ipairs(laid_out.stages) do
      has_layout = has_layout or vim.startswith(stage, "layout:")
    end
    h.assert_true("layout cache is independently owned", has_layout)

    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "| changed | two |" })
    local changed = parser.parse_all(buf, { backend = "lua" })
    h.assert_eq("changedtick invalidates parsed value", changed[1].rows[1][1].text, "changed")
  end)
end)

h.test("v0.4 buffer wipe releases parser layout and discovery state", function()
  local plugin = require("markdown-table-wrap")
  local cache = require("markdown-table-wrap.cache")
  plugin.setup({ auto_preview = false, discovery = { backend = "lua" } })
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "| A | B |", "| --- | --- |", "| one | two |" })
  local model = require("markdown-table-wrap.parser").parse_all(buf)[1]
  h.assert_true("parse cache exists before wipe", cache.inspect(buf).entries > 0)
  require("markdown-table-wrap.render").render_table(model, plugin.config)
  vim.api.nvim_buf_delete(buf, { force = true })
  h.assert_eq("all buffer cache stages released", cache.inspect(buf).entries, 0)
  h.assert_eq(
    "discovery status released",
    require("markdown-table-wrap.discovery").status(buf).fallback_reason,
    "not run"
  )
end)
