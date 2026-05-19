local h = require("tests.helpers")

h.test("system render chain only conceals detected table range", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    row_separator = true,
    inline_viewport_scrolling = false,
  })

  h.with_buffer({
    "pipe prose | should stay visible",
    "| A | B |",
    "| --- | --- |",
    "| `code` | [link](url)<br>**bold** |",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local concealed_rows = {}
    local styled = {}

    for _, mark in ipairs(marks) do
      local row = mark[2]
      local details = mark[4] or {}
      if details.conceal == "" then
        concealed_rows[row] = true
      end
      for _, chunk in ipairs(details.virt_text or {}) do
        styled[chunk[2]] = true
      end
      for _, virt_line in ipairs(details.virt_lines or {}) do
        for _, chunk in ipairs(virt_line) do
          styled[chunk[2]] = true
        end
      end
    end

    h.assert_false("adjacent prose is not concealed", concealed_rows[0])
    h.assert_true("header concealed", concealed_rows[1])
    h.assert_true("separator concealed", concealed_rows[2])
    h.assert_true("row concealed", concealed_rows[3])
    h.assert_true("code styled through chain", styled.MarkdownTableWrapCode)
    h.assert_true("link styled through chain", styled.MarkdownTableWrapLink)
    h.assert_true("bold styled through chain", styled.MarkdownTableWrapBold)

    inline.clear(buf)
  end)
end)
