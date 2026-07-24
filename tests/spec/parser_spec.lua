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

h.test("parser rejects invalid GFM delimiter rows", function()
  local parser = require("markdown-table-wrap.parser")

  h.with_buffer({
    "| A | B |",
    "| - | -- |",
    "| 1 | 2 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 1)
    h.assert_false("short delimiter rejected", parsed)
  end)

  h.with_buffer({
    "| A | B |",
    "| --- |",
    "| 1 | 2 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 1)
    h.assert_false("mismatched delimiter count rejected", parsed)
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
