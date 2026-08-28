local h = require("tests.helpers")

h.test("optional Reader sticky header is window-local and source-safe", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, reader = { sticky_header = true } })

  h.with_buffer({
    "Intro prose",
    "",
    "| Name | Value |",
    "| --- | --- |",
    "| one | two |",
    "",
    "After prose",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.wo.winbar = "source-winbar"
    local reader_bufnr = plugin.reader_preview()
    h.assert_true("Reader opened for sticky-header test", reader.is_reader(reader_bufnr))
    vim.api.nvim_win_set_cursor(0, { 4, 2 })
    reader.update_sticky_header(reader_bufnr)
    h.assert_true("sticky header is visible over the table", vim.wo.winbar:find("Name", 1, true) ~= nil)

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    reader.update_sticky_header(reader_bufnr)
    h.assert_eq("sticky header restores the original winbar outside a table", vim.wo.winbar, "source-winbar")

    plugin.close_reader()
    h.assert_eq("Source winbar is restored after Reader close", vim.wo.winbar, "source-winbar")
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("Reader cell index resolves wrapped segments without scanning unrelated cells", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, min_col_width = 3, max_col_width = 6, max_width_ratio = 1 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | alpha beta gamma |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_width(0, 40)
    local reader_bufnr = plugin.reader_preview()
    local state = reader.get_state(reader_bufnr)
    local target
    for row, object in ipairs(state.line_objects) do
      for _, cell in ipairs(type(object) == "table" and object.cells or {}) do
        if cell.row_index == 1 and cell.column_index == 2 then
          target = { row, cell.start_col }
          break
        end
      end
      if target then
        break
      end
    end
    vim.api.nvim_win_set_cursor(0, target)
    local resolved = reader.cell_at_cursor(reader_bufnr)
    h.assert_true("indexed logical cell resolves", resolved ~= nil)
    h.assert_true("logical cell spans multiple rendered lines", resolved.render_end_row > resolved.render_start_row)
    local key = table.concat({ resolved.table_id, resolved.row_index, resolved.column_index }, ":")
    h.assert_true("cell segment index exists", state.cell_segments[key] ~= nil)
    h.assert_true("cell segment index retains every line", #state.cell_segments[key] >= 2)
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("Reader help exposes copy and viewport ergonomics", function()
  local plugin = require("markdown-table-wrap")
  local inspect = require("markdown-table-wrap.inspect")
  plugin.setup({ auto_preview = false })
  h.with_buffer({ "| A | B |", "| --- | --- |", "| one | two |" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local context = require("markdown-table-wrap.context").resolve({ bufnr = buf })
    local help_buf = inspect.open_help(context)
    local lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    h.assert_true("help lists rendered cell copy", text:find("YankCell", 1, true) ~= nil)
    h.assert_true("help lists structured export", text:find("Export", 1, true) ~= nil)
    local win = vim.fn.win_findbuf(help_buf)[1]
    if win then
      vim.api.nvim_win_close(win, true)
    end
  end)
end)
