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

h.test("render keeps borders aligned for code-wrapped link labels", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| Week | Overview | Day 1 | Done |",
    "| --- | --- | --- | --- |",
    "| 1 | [overview](curriculum/week-01/overview.md) | [day-01](curriculum/week-01/day-01.md) | first |",
    "| 2 | [`overview`](curriculum/week-02/overview.md) | [`day-01`](curriculum/week-02/day-02.md) | second |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 100)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 40,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = false,
    })

    local first_body = rendered.line_objects[4].text
    local second_body = rendered.line_objects[5].text
    h.assert_eq("code-wrapped link has no concealed delimiters", second_body:find("`", 1, true), nil)
    h.assert_eq(
      "code-wrapped and plain rows have equal width",
      vim.api.nvim_strwidth(first_body),
      vim.api.nvim_strwidth(second_body)
    )
    h.assert_eq("code-wrapped row keeps table width", vim.api.nvim_strwidth(second_body), rendered.width)
  end)
end)

h.test("render wraps oversized inline code in a narrow window", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local original_columns = vim.o.columns

  vim.o.columns = 60
  local ok, err = pcall(function()
    h.with_buffer({
      "| 语义 | 当前实验候选 | 能支持的最小结论 | 不能直接支持 |",
      "|---|---|---|---|",
      "| request/attempt | `tracepoint:syscalls:sys_enter_execve` | 进程提交了执行请求 | 请求成功、最终 file object |",
      "| syscall return | `tracepoint:syscalls:sys_exit_execve` | syscall 返回值和 entry 的时间/PID 关系 | 所有内核内部路径、策略决定 |",
      "| success/lifecycle | `tracepoint:sched:sched_process_exec` | 成功映像切换的生命周期证据候选 | 失败请求集合 |",
      "| decision | BPF LSM exec-related hook（另行 discovery） | 某安全决策点的 allow/deny 语义候选 | 完整审计 coverage |",
    }, function(buf)
      local parsed = parser.parse_at_cursor(buf, 3)
      local rendered = render.render_table(parsed, {
        max_width_ratio = 0.9,
        min_col_width = 8,
        max_col_width = 50,
        fit_to_window = true,
        use_unicode_border = true,
        table_border = "rounded",
        row_separator = false,
      })

      local code_line_count = 0
      for index, line in ipairs(rendered.lines) do
        h.assert_true("narrow rendered line fits " .. index, vim.api.nvim_strwidth(line) <= rendered.width)
        for _, chunk in ipairs(rendered.line_objects[index].chunks or {}) do
          if chunk.hl_group == "MarkdownTableWrapCode" then
            code_line_count = code_line_count + 1
            break
          end
        end
      end

      h.assert_true("oversized code is rendered across multiple lines", code_line_count > 1)
    end)
  end)
  vim.o.columns = original_columns
  if not ok then
    error(err, 0)
  end
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

h.test("render can shrink below preferred column width to fit the window", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B | C | D | E | F | G | H |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    "| alpha beta gamma | one two three | 中文内容很长 | final content | fifth column | sixth column | seventh column | eighth column |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 8,
      max_col_width = 50,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    for index, line in ipairs(rendered.lines) do
      h.assert_true("fit-to-window rendered line " .. index, vim.api.nvim_strwidth(line) <= 72)
    end
  end)
end)

h.test("render keeps every source row mapped when cells wrap", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| alpha beta gamma delta | one |",
    "| two | three |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 36)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 8,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    local first_row_lines = 0
    for _, source_lnum in ipairs(rendered.source_lnums) do
      if source_lnum == 3 then
        first_row_lines = first_row_lines + 1
      end
    end
    h.assert_true("wrapped source row maps to multiple rendered lines", first_row_lines > 1)
    h.assert_eq("final border maps to final source row", rendered.source_lnums[#rendered.source_lnums], 4)
  end)
end)

h.test("render respects preferred widths when fit-to-window is disabled", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| one | two | three |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 30)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.5,
      min_col_width = 10,
      max_col_width = 10,
      fit_to_window = false,
      use_unicode_border = true,
      table_border = "single",
      row_separator = false,
    })

    h.assert_true("table can exceed requested viewport", rendered.width > 15)
    h.assert_eq("top border keeps stable width", vim.api.nvim_strwidth(rendered.lines[1]), rendered.width)
    h.assert_eq(
      "bottom border keeps stable width",
      vim.api.nvim_strwidth(rendered.lines[#rendered.lines]),
      rendered.width
    )
  end)
end)

h.test("render highlights every wrapped header line as a header", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| a header that wraps | B |",
    "| --- | --- |",
    "| value | other |",
  }, function(source_buf)
    local parsed = parser.parse_at_cursor(source_buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 6,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    local header_lines = 0
    for _, line_obj in ipairs(rendered.line_objects) do
      if line_obj.is_header then
        header_lines = header_lines + 1
      end
    end
    h.assert_true("header wraps across multiple rendered lines", header_lines > 1)

    local rendered_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(rendered_buf, 0, -1, false, rendered.lines)
    local namespace = vim.api.nvim_create_namespace("markdown-table-wrap-test-wrapped-header")
    render.apply_highlights(rendered_buf, rendered.line_objects, {}, { namespace = namespace })

    local marks = vim.api.nvim_buf_get_extmarks(rendered_buf, namespace, 0, -1, { details = true })
    local highlighted_header_lines = 0
    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details.priority == 10 and details.hl_group == "MarkdownTableWrapHeader" then
        highlighted_header_lines = highlighted_header_lines + 1
      end
    end

    h.assert_eq("every wrapped header line uses header highlight", highlighted_header_lines, header_lines)
    vim.api.nvim_buf_delete(rendered_buf, { force = true })
  end)
end)

h.test("render merges contiguous border highlights for large tables", function()
  local render = require("markdown-table-wrap.render")
  local line_count = 1000
  local lines = {}
  local line_objects = {}

  for _ = 1, line_count do
    local line =
      "├────────────────────────┼────────────────────────┤"
    table.insert(lines, line)
    table.insert(line_objects, { text = line, chunks = {} })
  end

  h.with_buffer(lines, function(buf)
    local namespace = vim.api.nvim_create_namespace("markdown-table-wrap-test-border-ranges")
    render.apply_highlights(buf, line_objects, {}, { namespace = namespace })

    local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
    local border_marks = 0
    for _, mark in ipairs(marks) do
      if mark[4].hl_group == "MarkdownTableWrapBorder" then
        border_marks = border_marks + 1
      end
    end

    h.assert_eq("one merged border range per rendered line", border_marks, line_count)
    h.assert_true("extmark count stays linear with a small constant", #marks <= line_count * 2)
  end)
end)
