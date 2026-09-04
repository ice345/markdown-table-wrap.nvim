local h = require("tests.helpers")

h.test("parser handles escaped pipes and code pipes", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| x\\|y | `a|b` | z |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("parsed table", parsed ~= nil)
    h.assert_eq("escaped pipe", parsed.rows[1][1].text, "x|y")
    h.assert_eq("code pipe", parsed.rows[1][2].text, "a|b")
    h.assert_eq("code pipe kind", parsed.rows[1][2].spans[1].kind, "code")
  end)
end)

h.test("parser keeps pipes inside multi-backtick code spans", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| ``a|b`` | c |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("multi-backtick table parsed", parsed ~= nil)
    h.assert_eq("multi-backtick pipe", parsed.rows[1][1].text, "a|b")
    h.assert_eq("multi-backtick code kind", parsed.rows[1][1].spans[1].kind, "code")
  end)
end)

h.test("shared UTF-8 scanner does not skip structural pipes after invalid bytes", function()
  local parser = require("markdown-table-wrap.parser")
  local invalid = string.char(0xFF)
  local tables = parser.parse_lines({ invalid .. " A | B", "--- | ---", "one | two" })
  h.assert_eq("invalid byte table still parses", #tables, 1)
  h.assert_eq("pipe after invalid byte still separates columns", #tables[1].header, 2)
  h.assert_eq("second cell remains intact", tables[1].rows[1][2].text, "two")
end)

h.test("parser supports optional outer pipes and alignment", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "A | B | C",
    ":--- | :---: | ---:",
    "left | center | right",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 2)
    h.assert_true("parsed optional pipe table", parsed ~= nil)
    h.assert_eq("column count", #parsed.header, 3)
    h.assert_eq("left align", parsed.align[1], "left")
    h.assert_eq("center align", parsed.align[2], "center")
    h.assert_eq("right align", parsed.align[3], "right")
    h.assert_eq("row cell", parsed.rows[1][3].text, "right")
  end)
end)

h.test("parser trims whitespace around outer pipes", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "   | A | B |   ",
    "   | :--- | ---: |   ",
    "   | left | right |   ",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 2)
    h.assert_true("whitespace outer pipe table parsed", parsed ~= nil)
    h.assert_eq("whitespace outer pipe column count", #parsed.header, 2)
    h.assert_eq("whitespace outer pipe first header", parsed.header[1].text, "A")
    h.assert_eq("whitespace outer pipe second row cell", parsed.rows[1][2].text, "right")
    h.assert_eq("whitespace outer pipe left alignment", parsed.align[1], "left")
    h.assert_eq("whitespace outer pipe right alignment", parsed.align[2], "right")
  end)
end)

h.test("parser does not mistake a whitespace-padded escaped pipe for an outer pipe", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "A | B",
    "--- | ---",
    "one | escaped\\|   ",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("escaped trailing pipe table parsed", parsed ~= nil)
    h.assert_eq("escaped trailing pipe cell count", #parsed.rows[1], 2)
    h.assert_eq("escaped trailing pipe preserved", parsed.rows[1][2].text, "escaped|")
  end)
end)

h.test("parser normalizes missing and extra cells", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one |",
    "| one | two | three |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_eq("missing cell empty", parsed.rows[1][2].text, "")
    h.assert_eq("extra cell ignored", #parsed.rows[2], 2)
    h.assert_eq("second cell preserved", parsed.rows[2][2].text, "two")
  end)
end)

h.test("parser supports GFM Example 202 body rows without pipes", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| abc | def |",
    "| --- | --- |",
    "| bar | baz |",
    "bar",
    "",
    "bar",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 4)
    h.assert_true("pipe-free body row belongs to table", parsed ~= nil)
    h.assert_eq("GFM table stops at blank line", parsed.end_lnum, 4)
    h.assert_eq("GFM body row count", #parsed.rows, 2)
    h.assert_eq("GFM missing cell first value", parsed.rows[2][1].text, "bar")
    h.assert_eq("GFM missing cell normalized", parsed.rows[2][2].text, "")
    h.assert_false("paragraph after blank is not table row", parser.parse_at_cursor(buf, 6))
  end)
end)

h.test("parser keeps inline HTML at the start of a body row", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "A | B",
    "--- | ---",
    "<em>one</em> | two",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("inline HTML row belongs to table", parsed ~= nil)
    h.assert_eq("inline HTML row reaches table end", parsed.end_lnum, 3)
    h.assert_eq("inline HTML text is preserved", parsed.rows[1][1].text, "<em>one</em>")
  end)
end)

h.test("parser rejects table-like paragraphs without separator", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "a | b | c",
    "this is not | a table | row",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 1)
    h.assert_false("no separator no table", parsed)
  end)
end)

h.test("parser accepts GFM-compliant short delimiter rows", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B |",
    "| - | -- |",
    "| 1 | 2 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 1)
    h.assert_true("short delimiter accepted", parsed ~= nil)
    h.assert_eq("short delimiter column count", #parsed.header, 2)
    h.assert_eq("short delimiter first alignment", parsed.align[1], "left")
    h.assert_eq("short delimiter second alignment", parsed.align[2], "left")
  end)
end)

h.test("parser rejects mismatched delimiter column count", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B |",
    "| --- |",
    "| 1 | 2 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 1)
    h.assert_false("mismatched delimiter count rejected", parsed)
  end)
end)

h.test("discovery keeps scanning after a rejected table-like block", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "- | A | B |",
    "  | --- | --- |",
    "| Real | Table |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    local tables = parser.parse_all(buf)
    h.assert_eq("real table after rejected list candidate is discovered", #tables, 1)
    h.assert_eq("real table starts at its own header", tables[1].start_lnum, 3)
    h.assert_eq("real table reaches its body row", tables[1].end_lnum, 5)
  end)
end)

h.test("parser does not consume adjacent pipe paragraphs", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "prefix | not table",
    "",
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "suffix | not table",
  }, function(buf)
    local tables = parser.parse_all(buf)
    h.assert_eq("only one table", #tables, 1)
    h.assert_eq("table start after paragraph", tables[1].start_lnum, 3)
    h.assert_eq("table end before paragraph", tables[1].end_lnum, 5)
  end)
end)

h.test("parser stops tables at new block-level structures", function()
  local parser = require("markdown-table-wrap.parser")

  local cases = {
    { label = "blockquote", line = "> quote | text" },
    { label = "heading", line = "## Heading | text" },
    { label = "list", line = "- item | text" },
    { label = "thematic break", line = "***" },
    { label = "HTML block", line = "<div>block | text</div>" },
    { label = "link reference", line = "[ref]: https://example.com/a|b" },
  }

  for _, case in ipairs(cases) do
    h.with_buffer({
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
      case.line,
    }, function(buf)
      local parsed = parser.parse_at_cursor(buf, 3)
      h.assert_true(case.label .. " preceding table parsed", parsed ~= nil)
      h.assert_eq(case.label .. " ends table", parsed.end_lnum, 3)
      h.assert_false(case.label .. " is not consumed", parser.parse_at_cursor(buf, 4))
    end)
  end
end)

h.test("parser supports blockquote tables and rejects list-contained tables", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "> A | B",
    "> --- | ---",
    "> one | two",
    "",
    "- A | B",
    "  --- | ---",
  }, function(buf)
    local tables = parser.parse_all(buf)
    h.assert_eq("blockquote table parses once", #tables, 1)
    h.assert_eq("blockquote container kind", tables[1].container.kind, "blockquote")
    h.assert_eq("blockquote container depth", tables[1].container.depth, 1)
    h.assert_eq("list-contained table stays unsupported", tables[1].end_lnum, 3)
    h.assert_false("list header is not parsed", parser.parse_at_cursor(buf, 5))
  end)
end)

h.test("blockquote table spans map cells and inline tokens to Source bytes", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    " > | 名称 | Link |",
    ">  | --- | --- |",
    "  > | 值 | [site](https://example.com) |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("spaced blockquote table parsed", parsed ~= nil)
    h.assert_eq("first header Source slice", parsed.header[1].source_span.start_col, 5)
    h.assert_eq("body link Source start", parsed.rows[1][2].source_span.start_col, 12)
    local line = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
    local span = parsed.rows[1][2].source_span
    h.assert_eq("body Source slice is exact", line:sub(span.start_col + 1, span.end_col), "[site](https://example.com)")
    h.assert_eq("link token uses physical Source column", parsed.rows[1][2].tokens[1].source_start_col, 12)
  end)
end)

h.test("parser supports nested blockquotes and pipe-free quoted body rows", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "> > | A | B |",
    ">> | --- | --- |",
    "> > one",
    "> outside | depth",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("nested blockquote parsed", parsed ~= nil)
    h.assert_eq("nested quote depth", parsed.container.depth, 2)
    h.assert_eq("pipe-free row value", parsed.rows[1][1].text, "one")
    h.assert_eq("pipe-free row missing cell", parsed.rows[1][2].text, "")
    h.assert_eq("quote depth change ends table", parsed.end_lnum, 3)
  end)
end)

h.test("parser ignores quoted table-shaped text inside quoted fences", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "> ```markdown",
    "> | Code | Table |",
    "> | --- | --- |",
    "> | one | two |",
    "> ```",
    "> | Real | Table |",
    "> | --- | --- |",
    "> | yes | rendered |",
  }, function(buf)
    h.assert_false("quoted fenced table is ignored", parser.parse_at_cursor(buf, 3))
    local tables = parser.parse_all(buf)
    h.assert_eq("one quoted table remains", #tables, 1)
    h.assert_eq("quoted table starts after fence", tables[1].start_lnum, 6)
  end)
end)

h.test("top-level fences keep quote-shaped code inside the same fence", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "```markdown",
    "> | Code | Table |",
    "> | --- | --- |",
    "> | one | two |",
    "```",
    "| Real | Table |",
    "| --- | --- |",
    "| yes | rendered |",
  }, function(buf)
    h.assert_false("quote-shaped fenced content is ignored", parser.parse_at_cursor(buf, 3))
    local tables = parser.parse_all(buf)
    h.assert_eq("only post-fence table remains", #tables, 1)
    h.assert_eq("post-fence table starts after closer", tables[1].start_lnum, 6)
  end)
end)

h.test("blockquote tables resolve blockquote reference definitions", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "> | A | B |",
    "> | --- | --- |",
    "> | [site][ref] | two |",
    ">",
    "> [ref]: https://example.com",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    h.assert_true("quoted reference table parsed", parsed ~= nil)
    h.assert_eq("quoted reference target resolved", parsed.rows[1][1].tokens[1].target, "https://example.com")
  end)
end)

h.test("parser starts at header when pipe paragraph touches table", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "not a table | just prose",
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    local prose = parser.parse_at_cursor(buf, 1)
    h.assert_false("prose line rejected", prose)

    local parsed = parser.parse_at_cursor(buf, 2)
    h.assert_true("adjacent table parsed", parsed ~= nil)
    h.assert_eq("strict table start", parsed.start_lnum, 2)
    h.assert_eq("strict table end", parsed.end_lnum, 4)
    h.assert_eq("header preserved", parsed.header[1].text, "A")
  end)
end)

h.test("parser finds all tables", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "# doc",
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "paragraph",
    "| C | D |",
    "| --- | --- |",
    "| 3 | 4 |",
  }, function(buf)
    local tables = parser.parse_all(buf)
    h.assert_eq("table count", #tables, 2)
    h.assert_eq("first table start", tables[1].start_lnum, 2)
    h.assert_eq("second table start", tables[2].start_lnum, 7)
  end)
end)

h.test("parser ignores table-shaped text inside fenced code blocks", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "```lua",
    "| Example | Value |",
    "| --- | --- |",
    "| one | two |",
    "```",
    "",
    "~~~markdown",
    "| Also | Code |",
    "| --- | --- |",
    "| three | four |",
    "~~~",
    "",
    "| Real | Table |",
    "| --- | --- |",
    "| yes | rendered |",
  }, function(buf)
    local first, message = parser.parse_at_cursor(buf, 3)
    h.assert_false("backtick fenced table is ignored", first)
    h.assert_true("fenced error explains boundary", message:find("fenced code block", 1, true) ~= nil)
    h.assert_false("tilde fenced table is ignored", parser.parse_at_cursor(buf, 9))

    local tables = parser.parse_all(buf)
    h.assert_eq("only real table is collected", #tables, 1)
    h.assert_eq("real table starts after fences", tables[1].start_lnum, 13)
  end)
end)

h.test("parser only closes fenced code with a bare fence marker", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "```lua",
    "| Code | Table |",
    "| --- | --- |",
    "| one | two |",
    "``` still code",
    "| Also | Code |",
    "| --- | --- |",
    "| three | four |",
    "```   ",
    "",
    "| Real | Table |",
    "| --- | --- |",
    "| yes | rendered |",
  }, function(buf)
    local inside, message = parser.parse_at_cursor(buf, 7)
    h.assert_false("nonempty fence tail does not close block", inside)
    h.assert_true("invalid closer remains fenced", message:find("fenced code block", 1, true) ~= nil)

    local tables = parser.parse_all(buf)
    h.assert_eq("only post-fence table collected", #tables, 1)
    h.assert_eq("bare closer permits following table", tables[1].start_lnum, 11)
  end)
end)

h.test("parse_all reads the buffer once for large pipe-shaped prose", function()
  local parser = require("markdown-table-wrap.parser")
  local lines = {}

  for index = 1, 2000 do
    lines[index] = string.format("prose %d | still not a table", index)
  end

  vim.list_extend(lines, {
    "",
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  })

  h.with_buffer(lines, function(buf)
    local original_get_lines = vim.api.nvim_buf_get_lines
    local get_lines_calls = 0
    vim.api.nvim_buf_get_lines = function(...)
      get_lines_calls = get_lines_calls + 1
      return original_get_lines(...)
    end

    local ok, tables = pcall(parser.parse_all, buf)
    vim.api.nvim_buf_get_lines = original_get_lines

    if not ok then
      error(tables)
    end

    h.assert_eq("large document table count", #tables, 1)
    h.assert_eq("parse_all buffer reads", get_lines_calls, 1)
  end)
end)
