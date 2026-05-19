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
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    h.assert_true("inline marks", #marks > 0)
    h.assert_eq("conceallevel set", vim.wo.conceallevel, 2)
    h.assert_eq("concealcursor set", vim.wo.concealcursor, "nvc")

    inline.clear(buf)
    h.assert_eq("conceallevel restored", vim.wo.conceallevel, 0)
    h.assert_eq("concealcursor restored", vim.wo.concealcursor, "")
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
