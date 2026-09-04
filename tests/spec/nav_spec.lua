local h = require("tests.helpers")

h.test("navigation keeps escaped pipes and multi-backtick code inside one cell", function()
  local nav = require("markdown-table-wrap.nav")

  local line = "| ``a|b`` | x\\|y | final |"
  local spans = nav.spans(line)

  h.assert_eq("three cells are found", #spans, 3)
  h.assert_eq("first cell includes code pipe", line:sub(spans[1].start_col + 1, spans[1].end_col), "``a|b``")
  h.assert_eq("second cell includes escaped pipe", line:sub(spans[2].start_col + 1, spans[2].end_col), "x\\|y")
  h.assert_eq("third cell is preserved", line:sub(spans[3].start_col + 1, spans[3].end_col), "final")
end)

h.test("navigation spans ignore blockquote markers and preserve UTF-8 cells", function()
  local nav = require("markdown-table-wrap.nav")
  local line = "  > | 名称 | x\\|y |"
  local spans = nav.spans(line)
  h.assert_eq("quoted table has two cells", #spans, 2)
  h.assert_eq("first quoted cell is exact", line:sub(spans[1].start_col + 1, spans[1].end_col), "名称")
  h.assert_eq("second quoted cell is exact", line:sub(spans[2].start_col + 1, spans[2].end_col), "x\\|y")
end)

h.test("Float navigation shifts a wide-table viewport to reveal the target cell", function()
  local plugin = require("markdown-table-wrap")
  local nav = require("markdown-table-wrap.nav")
  plugin.setup({
    auto_preview = false,
    min_col_width = 4,
    max_col_width = 12,
    wide_table = { mode = "viewport", viewport = { start_column = 1, column_count = 1 } },
  })

  h.with_buffer({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| one | two | three |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    plugin.float_preview()
    local first
    for row, object in ipairs(plugin.state.float_rendered.line_objects or {}) do
      for _, cell in ipairs(type(object) == "table" and object.cells or {}) do
        if cell.row_index == 0 and cell.column_index == 1 then
          first = { row, cell.start_col }
        end
      end
    end
    vim.api.nvim_win_set_cursor(plugin.state.win, first)
    h.assert_true("Float moves to a hidden adjacent column", nav.move_horizontal(1))
    local context = plugin.get_state(plugin.state.buf)
    h.assert_eq("Float viewport now focuses column two", context.cell.index, 2)
    h.assert_deep_eq("Float viewport renders column two", plugin.state.float_rendered.visible_columns, { 2 })
    plugin.close_preview()
  end)
end)

h.test("navigation moves across data rows and skips the separator", function()
  local nav = require("markdown-table-wrap.nav")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
    "| three | four |",
  }, function(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_true("move right", nav.move_horizontal(1))
    h.assert_deep_eq("right enters second header cell", vim.api.nvim_win_get_cursor(0), { 1, 6 })

    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_true("move down skips separator", nav.move_vertical(1))
    h.assert_deep_eq("down lands in first data row", vim.api.nvim_win_get_cursor(0), { 3, 2 })

    vim.api.nvim_win_set_cursor(0, { 4, 2 })
    h.assert_true("move down clamps at final row", nav.move_vertical(1))
    h.assert_deep_eq("bottom remains final row", vim.api.nvim_win_get_cursor(0), { 4, 2 })
    h.assert_eq("cell text follows cursor", nav.current_cell_text(), "three")
  end)
end)

h.test("navigation follows logical cells in Reader and Float views", function()
  local plugin = require("markdown-table-wrap")
  local nav = require("markdown-table-wrap.nav")
  local parser = require("markdown-table-wrap.parser")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, min_col_width = 4, max_col_width = 12 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local table_info = parser.parse_at_cursor(source_bufnr, 3)
    local reader_bufnr = plugin.reader_preview()
    h.assert_true(
      "Reader starts on first header cell",
      reader.focus_source_cell(reader_bufnr, table_info.start_lnum, 1, table_info.id, 0)
    )
    h.assert_true("Reader moves horizontally", nav.move_horizontal(1))
    local reader_cell = reader.cell_at_cursor(reader_bufnr)
    h.assert_eq("Reader horizontal target is logical column two", reader_cell.column_index, 2)
    h.assert_true("Reader moves vertically", nav.move_vertical(1))
    reader_cell = reader.cell_at_cursor(reader_bufnr)
    h.assert_eq("Reader vertical target is first body row", reader_cell.row_index, 1)
    h.assert_eq("Reader vertical movement keeps the column", reader_cell.column_index, 2)
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil

    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    plugin.float_preview()
    local rendered = plugin.state.float_rendered
    local first_header
    for row, object in ipairs(rendered.line_objects or {}) do
      for _, cell in ipairs(type(object) == "table" and object.cells or {}) do
        if cell.row_index == 0 and cell.column_index == 1 then
          first_header = { row, cell.start_col }
          break
        end
      end
      if first_header then
        break
      end
    end
    h.assert_true("Float header cell exists", first_header ~= nil)
    vim.api.nvim_win_set_cursor(plugin.state.win, first_header)
    h.assert_true("Float moves horizontally", nav.move_horizontal(1))
    local context = plugin.get_state(plugin.state.buf)
    h.assert_eq("Float horizontal target is logical column two", context.cell.index, 2)
    h.assert_true("Float moves vertically", nav.move_vertical(1))
    context = plugin.get_state(plugin.state.buf)
    h.assert_eq("Float vertical target is first body row", context.cell.row_index, 1)
    h.assert_eq("Float vertical movement keeps the column", context.cell.index, 2)
    plugin.close_preview()
  end)
end)
