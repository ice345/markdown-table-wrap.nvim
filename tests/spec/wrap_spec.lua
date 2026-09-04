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

h.test("wrap keeps fitting code spans intact and splits oversized spans", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local fitting = wrap.wrap_cell(markdown.parse_inline("`code value/with/path`"), 20)
  h.assert_eq("fitting code span stays on one line", #fitting, 1)
  h.assert_eq("fitting code span keeps its text", fitting[1].text, "code value/with/path")

  local lines = wrap.wrap_cell(markdown.parse_inline("`tracepoint:sched:sched_process_exec`"), 12)
  local pieces = {}

  h.assert_true("oversized code span wraps", #lines > 1)
  for index, line in ipairs(lines) do
    h.assert_true("oversized code line fits " .. index, vim.api.nvim_strwidth(line.text) <= 12)
    h.assert_true("oversized code line keeps code styling " .. index, line.spans[1] ~= nil)
    h.assert_eq("oversized code span kind " .. index, line.spans[1].kind, "code")
    table.insert(pieces, line.text)
  end

  h.assert_eq("oversized code span keeps its text", table.concat(pieces), "tracepoint:sched:sched_process_exec")
end)

h.test("wrap keeps ordinary inline code spans styled after a hard break", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("before `code`<br>after"), 12)

  local found_code = false
  for _, line in ipairs(lines) do
    for _, span in ipairs(line.spans) do
      if span.kind == "code" then
        found_code = true
      end
    end
  end

  h.assert_true("hard-break code span remains styled", found_code)
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

h.test("wrap prefers common Chinese sentence punctuation", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local value = "第一段。第二段！第三段？第四段：第五段"
  local lines = wrap.wrap_cell(markdown.parse_inline(value), 10)
  local joined = {}
  local punctuation_breaks = 0

  for index, line in ipairs(lines) do
    h.assert_true("Chinese punctuation line fits " .. index, vim.api.nvim_strwidth(line.text) <= 10)
    table.insert(joined, line.text)
    for _, punctuation in ipairs({ "。", "！", "？", "：" }) do
      if vim.endswith(line.text, punctuation) then
        punctuation_breaks = punctuation_breaks + 1
        break
      end
    end
  end
  h.assert_eq("Chinese punctuation wrapping preserves text", table.concat(joined), value)
  h.assert_true("Chinese punctuation is used as a preferred boundary", punctuation_breaks >= 3)
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
