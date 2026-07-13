local h = require("tests.helpers")

h.test("inline whole-buffer render uses extmarks and conceal options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| **bold** | [link](url) |",
    "",
    "| C | D |",
    "| --- | --- |",
    "| `code` | ~~strike~~ |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.conceallevel = 0
    vim.wo.concealcursor = ""
    vim.wo.wrap = true
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    h.assert_true("inline marks", #marks > 0)
    h.assert_eq("conceallevel set", vim.wo.conceallevel, 2)
    h.assert_eq("concealcursor set", vim.wo.concealcursor, "nvc")
    h.assert_false("wrap disabled while inline replace is active", vim.wo.wrap)

    inline.clear(buf)
    h.assert_eq("conceallevel restored", vim.wo.conceallevel, 0)
    h.assert_eq("concealcursor restored", vim.wo.concealcursor, "")
    h.assert_true("wrap restored", vim.wo.wrap)
  end)
end)

h.test("floating preview includes highlight extmarks", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| `code` | [link](url) |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      border = "rounded",
    })
    local float_buf, win = render.open_float(rendered, { border = "rounded" })
    local marks = vim.api.nvim_buf_get_extmarks(float_buf, -1, 0, -1, { details = true })
    h.assert_true("float highlight marks", #marks > 0)
    vim.api.nvim_win_close(win, true)
  end)
end)

h.test("floating preview gx opens the rendered link under the cursor", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [youtube](https://www.youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      border = "rounded",
    })
    local _, win = render.open_float(rendered, { border = "rounded" })
    local target = nil

    for row, line_object in ipairs(rendered.line_objects) do
      for _, chunk in ipairs(line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url then
          target = { row, chunk.start_col }
          break
        end
      end
      if target then
        break
      end
    end

    h.assert_true("floating link target", target ~= nil)
    vim.api.nvim_win_set_cursor(win, target)
    vim.cmd("normal gx")
    h.assert_eq("opened floating URL", opened, "https://www.youtube.com")
    vim.api.nvim_win_close(win, true)
  end)

  vim.ui.open = original_open
end)

h.test("floating preview preserves inline rendering in render_all mode", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_true("inline active before float", inline.is_active(buf))

    plugin.float_preview()
    h.assert_true("inline active after float", inline.is_active(buf))

    if plugin.state.win and vim.api.nvim_win_is_valid(plugin.state.win) then
      vim.api.nvim_win_close(plugin.state.win, true)
    end
    inline.clear(buf)
  end)
end)

h.test("inline viewport scroll changes rendered table slice", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    min_col_width = 4,
    max_col_width = 8,
    inline_viewport_scrolling = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | alpha beta gamma delta epsilon |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })

    local function first_overlay_text()
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[2] == 0 and mark[4] and mark[4].virt_text then
          local parts = {}
          for _, chunk in ipairs(mark[4].virt_text) do
            table.insert(parts, chunk[1])
          end
          return table.concat(parts)
        end
      end
      return ""
    end

    local before = first_overlay_text()
    vim.cmd("MarkdownTableScrollDown")
    local after = first_overlay_text()
    vim.cmd("MarkdownTableScrollBottom")
    local bottom = first_overlay_text()
    vim.cmd("MarkdownTableScrollTop")
    local top = first_overlay_text()

    h.assert_true("before has top border", before:find("╭", 1, true) ~= nil)
    h.assert_true("after scroll advances viewport", after ~= before)
    h.assert_true("bottom changes viewport", bottom ~= before)
    h.assert_eq("top restores viewport", top, before)

    inline.clear(buf)
  end)
end)

h.test("inline replace can use overlay or fixed window column virtual text", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  local function first_virtual_text_mark(buf)
    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      if mark[4] and mark[4].virt_text then
        return mark[4]
      end
    end
    return nil
  end

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    plugin.setup({
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
      inline_virtual_text = "overlay",
    })
    plugin.refresh_auto({ force = true })

    local overlay = first_virtual_text_mark(buf)
    h.assert_eq("overlay render mode", overlay.virt_text_pos, "overlay")
    h.assert_eq("overlay avoids fixed win col", overlay.virt_text_win_col, nil)

    inline.clear(buf)
    plugin.setup({
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
      inline_virtual_text = "win_col",
    })
    plugin.refresh_auto({ force = true })

    local win_col = first_virtual_text_mark(buf)
    h.assert_eq("win_col render mode", win_col.virt_text_win_col, 0)
    h.assert_eq("win_col reports fixed position", win_col.virt_text_pos, "win_col")

    inline.clear(buf)
  end)
end)

h.test("inline viewport toggle switches between sliced and full rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    min_col_width = 4,
    max_col_width = 8,
    inline_viewport_scrolling = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | alpha beta gamma delta epsilon |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })

    local function has_virt_lines()
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4] and mark[4].virt_lines then
          return true
        end
      end
      return false
    end

    h.assert_false("viewport mode avoids extra virt_lines", has_virt_lines())
    vim.cmd("MarkdownTableToggleInlineViewport")
    h.assert_false("viewport disabled", plugin.config.inline_viewport_scrolling)
    h.assert_true("full mode uses virt_lines", has_virt_lines())

    vim.cmd("MarkdownTableToggleInlineViewport")
    h.assert_true("viewport enabled", plugin.config.inline_viewport_scrolling)
    h.assert_false("viewport mode restored", has_virt_lines())

    inline.clear(buf)
  end)
end)

h.test("extra inline virtual lines keep their original rendered line index", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    inline_viewport_scrolling = false,
    row_separator = true,
  })

  h.with_buffer({
    "| 成员 | 分工 |",
    "| --- | --- |",
    "| 组长 | 项目规划 |",
    "| 成员 A | 数据集整理 |",
    "| 成员 B | Web 系统实现 |",
    "| 成员 C | 报告撰写 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local member_b_chunks = nil

    for _, mark in ipairs(marks) do
      for _, virt_line in ipairs((mark[4] or {}).virt_lines or {}) do
        local text = {}
        for _, chunk in ipairs(virt_line) do
          table.insert(text, chunk[1])
        end

        if table.concat(text):find("成员 B", 1, true) then
          member_b_chunks = virt_line
        end
      end
    end

    h.assert_true("member B rendered as extra virtual line", member_b_chunks ~= nil)

    local groups = {}
    for _, chunk in ipairs(member_b_chunks) do
      groups[chunk[2]] = true
    end

    h.assert_false("member B is not treated as table header", groups.MarkdownTableWrapHeader)
    h.assert_true("member B keeps normal inline highlight", groups.MarkdownTableWrapInline)

    inline.clear(buf)
  end)
end)

h.test("table link opener uses source cell urls", function()
  local nav = require("markdown-table-wrap.nav")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [YouTube](https://youtube.com/watch) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 12 })
    h.assert_true("open table link", nav.open_link())
    h.assert_eq("opened url", opened, "https://youtube.com/watch")
  end)

  vim.ui.open = original_open
end)

h.test("table link opener falls back to the only parsed table link", function()
  local nav = require("markdown-table-wrap.nav")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [youtube](https://www.youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    h.assert_true("open only parsed table link", nav.open_link())
    h.assert_eq("opened parsed table URL", opened, "https://www.youtube.com")
  end)

  vim.ui.open = original_open
end)
