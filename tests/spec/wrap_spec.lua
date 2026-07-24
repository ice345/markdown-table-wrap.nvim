local h = require("tests.helpers")

h.test("wrap preserves token spans", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("before `code` after"), 80)
  local found_code = false

  for _, span in ipairs(lines[1].spans) do
    if span.kind == "code" and lines[1].text:sub(span.start_col + 1, span.end_col) == "code" then
      found_code = true
    end
  end

  h.assert_true("wrapped code span", found_code)
end)

h.test("wrap keeps inline code spans indivisible", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("before `code value/with/path` after"), 12)

  local found_whole_code = false
  for _, line in ipairs(lines) do
    if line.text == "code value/with/path" then
      found_whole_code = true
    end
  end

  h.assert_true("code span not split", found_whole_code)
end)

h.test("wrap handles wide characters and hard breaks", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("中文中文<br>日本語English"), 8)

  h.assert_true("multiple hard break lines", #lines >= 2)
  for index, line in ipairs(lines) do
    h.assert_true("line width " .. index, vim.api.nvim_strwidth(line.text) <= 8)
  end
end)

h.test("wrap prefers punctuation boundaries and preserves link metadata", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines =
    wrap.wrap_cell(markdown.parse_inline("alpha, beta; [documentation](https://example.com/very/long/path)"), 12)
  local link_spans = 0

  h.assert_true("punctuation creates more than one display line", #lines > 1)
  for _, line in ipairs(lines) do
    for _, span in ipairs(line.spans) do
      if span.kind == "link" then
        link_spans = link_spans + 1
        h.assert_eq("wrapped link keeps URL", span.url, "https://example.com/very/long/path")
      end
    end
  end
  h.assert_true("wrapped link remains highlighted", link_spans > 0)
end)
