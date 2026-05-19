local h = require("tests.helpers")

h.test("render emits styled chunks", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| `code` | **bold** *italic* ~~strike~~ ==mark== [link](https://youtube.com) [[wiki]] ![alt](x.png) |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      link = {
        wiki = { icon = "W " },
        image = "I ",
        custom = {
          youtube = { pattern = "youtube", icon = "Y " },
        },
      },
    })

    local groups = {}
    for _, line in ipairs(rendered.line_objects) do
      for _, chunk in ipairs(line.chunks or {}) do
        groups[chunk.hl_group] = true
      end
    end

    h.assert_true("code chunk", groups.MarkdownTableWrapCode)
    h.assert_true("bold chunk", groups.MarkdownTableWrapBold)
    h.assert_true("italic chunk", groups.MarkdownTableWrapItalic)
    h.assert_true("strike chunk", groups.MarkdownTableWrapStrike)
    h.assert_true("mark chunk", groups.MarkdownTableWrapMark)
    h.assert_true("link chunk", groups.MarkdownTableWrapLink)
    h.assert_true("wiki link chunk", groups.MarkdownTableWrapWikiLink)
    h.assert_true("image chunk", groups.MarkdownTableWrapImage)

    local output = table.concat(rendered.lines, "\n")
    h.assert_true("custom link icon rendered", output:find("Y link", 1, true) ~= nil)
    h.assert_true("wiki icon rendered", output:find("W", 1, true) ~= nil and output:find("wiki", 1, true) ~= nil)
    h.assert_true("image icon rendered", output:find("I alt", 1, true) ~= nil)
  end)
end)

h.test("render output golden snapshot", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| 名称 | 说明 |",
    "| --- | --- |",
    "| Rc | `Rc<RefCell<T>>` 中文说明很长很长 |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 16,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    h.assert_eq(
      "golden top",
      rendered.lines[1],
      "╭──────┬──────────────────╮"
    )
    h.assert_eq("golden header", rendered.lines[2], "│ 名称 │ 说明             │")
    h.assert_true("golden has bottom", rendered.lines[#rendered.lines]:match("^╰") ~= nil)
  end)
end)

h.test("render alignment golden snapshot", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| L | C | R |",
    "| :--- | :---: | ---: |",
    "| x | y | z |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 3,
      max_col_width = 3,
      use_unicode_border = true,
      table_border = "single",
      row_separator = false,
    })

    h.assert_eq("alignment header", rendered.lines[2], "│ L   │  C  │   R │")
    h.assert_eq("alignment row", rendered.lines[4], "│ x   │  y  │   z │")
  end)
end)

h.test("render ascii border and no row separator", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "| 3 | 4 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 3,
      max_col_width = 3,
      use_unicode_border = false,
      table_border = "single",
      row_separator = false,
    })

    h.assert_eq("ascii top", rendered.lines[1], "+-----+-----+")
    h.assert_eq("ascii no row separator line count", #rendered.lines, 6)
  end)
end)

h.test("render mixed width cells stay within configured width", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 中日English | 中文中文EnglishEnglish |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 8,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    for index, line in ipairs(rendered.lines) do
      h.assert_true("mixed width rendered line " .. index, vim.api.nvim_strwidth(line) <= rendered.width)
    end
  end)
end)
