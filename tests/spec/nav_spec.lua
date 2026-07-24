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
