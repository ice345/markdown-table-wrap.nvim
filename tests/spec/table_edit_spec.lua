local h = require("tests.helpers")

local function setup_source(lines)
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  return plugin, buf
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function cleanup(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

h.test("format rewrites one table canonically in one Source change", function()
  local editor = require("markdown-table-wrap.table_edit")
  local _, buf = setup_source({
    "| A | Longer value |",
    "| --- | ---: |",
    "| x | two |",
  })
  vim.bo[buf].undolevels = -1
  vim.bo[buf].undolevels = 1000
  local before = vim.api.nvim_buf_get_changedtick(buf)
  h.assert_true("format succeeds", editor.format({ silent = true }))
  local after = lines(buf)
  h.assert_eq("formatted header keeps table columns", after[1], "| A   | Longer value |")
  h.assert_eq("formatted delimiter keeps right alignment", after[2], "| :--- | -----------: |")
  h.assert_eq("format is one changedtick step", after and vim.api.nvim_buf_get_changedtick(buf), before + 1)
  vim.cmd("undo")
  h.assert_deep_eq("format is one undo unit", lines(buf), {
    "| A | Longer value |",
    "| --- | ---: |",
    "| x | two |",
  })
  cleanup(buf)
end)

h.test("row operations add, move, and delete body rows", function()
  local editor = require("markdown-table-wrap.table_edit")
  local _, buf = setup_source({
    "| A | B |",
    "| --- | --- |",
    "| one | 1 |",
    "| two | 2 |",
  })
  h.assert_true("add row succeeds", editor.add_row({ values = { "three", "3" }, silent = true }))
  h.assert_true("new row is present", table.concat(lines(buf), "\n"):find("three", 1, true) ~= nil)
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  h.assert_true("move row down succeeds", editor.move_row_down({ silent = true }))
  h.assert_true("row moved below second row", lines(buf)[4]:find("one", 1, true) ~= nil)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  h.assert_true("delete row succeeds", editor.delete_row({ silent = true }))
  h.assert_true("deleted row is absent", table.concat(lines(buf), "\n"):find("one", 1, true) == nil)
  cleanup(buf)
end)

h.test("column operations add, move, delete, and toggle alignment", function()
  local editor = require("markdown-table-wrap.table_edit")
  local _, buf = setup_source({
    "| A | B |",
    "| --- | ---: |",
    "| one | 1 |",
  })
  h.assert_true("add column succeeds", editor.add_column({ index = 2, silent = true }))
  h.assert_true("added column delimiter exists", lines(buf)[2]:find("| :--- | :--- | ---: |", 1, true) ~= nil)
  h.assert_true("move column succeeds", editor.move_column_right({ index = 1, silent = true }))
  h.assert_true(
    "moved header order is visible",
    lines(buf)[1]:find("A", 1, true) ~= nil and lines(buf)[1]:find("B", 1, true) ~= nil
  )
  h.assert_true("toggle alignment succeeds", editor.toggle_alignment({ index = 2, silent = true }))
  h.assert_true("alignment marker changes", lines(buf)[2]:find(":", 1, true) ~= nil)
  h.assert_true("delete column succeeds", editor.delete_column({ index = 1, silent = true }))
  local parsed = require("markdown-table-wrap.parser").parse_at_cursor(buf, 3)
  h.assert_eq("table remains two columns", #parsed.header, 2)
  cleanup(buf)
end)

h.test("structural editing refuses excess cells without partial changes", function()
  local editor = require("markdown-table-wrap.table_edit")
  local original = {
    "| A | B |",
    "| --- | --- |",
    "| one | two | extra |",
  }
  local _, buf = setup_source(original)
  h.assert_false("unsafe format is rejected", editor.format({ silent = true }))
  h.assert_deep_eq("unsafe source remains unchanged", lines(buf), original)
  cleanup(buf)
end)

h.test("long-cell popup writes exact Source range and supports cancel", function()
  local editor = require("markdown-table-wrap.table_edit")
  local _, buf = setup_source({
    "| A | B |",
    "| --- | --- |",
    "| one | a long value |",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 11 })
  local popup_buf, popup_win = editor.open_cell_popup({ silent = true })
  h.assert_true("cell popup opens", popup_buf ~= false and vim.api.nvim_win_is_valid(popup_win))
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { "edited value" })
  h.assert_true("cell popup commit succeeds", editor.commit_cell_popup({ silent = true }))
  h.assert_true("popup closes after commit", not vim.api.nvim_win_is_valid(popup_win))
  h.assert_true("exact source cell is updated", lines(buf)[3]:find("edited value", 1, true) ~= nil)

  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  local cancel_buf, cancel_win = editor.open_cell_popup({ silent = true })
  h.assert_true("second popup opens", cancel_buf ~= false)
  vim.api.nvim_buf_set_lines(cancel_buf, 0, -1, false, { "discarded" })
  h.assert_true("popup cancel succeeds", editor.close_cell_popup())
  h.assert_true("cancel keeps Source value", lines(buf)[3]:find("edited value", 1, true) ~= nil)
  h.assert_false("cancel closes popup window", vim.api.nvim_win_is_valid(cancel_win))

  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  local stale_buf = editor.open_cell_popup({ silent = true })
  h.assert_true("stale popup opens", stale_buf ~= false)
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "| changed elsewhere | a long value |" })
  vim.api.nvim_buf_set_lines(stale_buf, 0, -1, false, { "must not overwrite" })
  h.assert_false("stale popup commit is rejected", editor.commit_cell_popup({ silent = true }))
  editor.close_cell_popup()
  h.assert_true("stale Source edit remains authoritative", lines(buf)[3]:find("changed elsewhere", 1, true) ~= nil)
  cleanup(buf)
end)

h.test("source editing actions and commands are exposed", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  for _, action in ipairs({
    "format_table",
    "add_row_table",
    "delete_row_table",
    "move_row_up_table",
    "move_row_down_table",
    "add_column_table",
    "delete_column_table",
    "move_column_left_table",
    "move_column_right_table",
    "toggle_alignment_table",
    "open_cell_popup_table",
  }) do
    h.assert_true("editing action exists: " .. action, require("markdown-table-wrap.actions").exists(action))
  end
  for _, command in ipairs({
    "MarkdownTableFormat",
    "MarkdownTableAddRow",
    "MarkdownTableDeleteRow",
    "MarkdownTableMoveRowUp",
    "MarkdownTableMoveRowDown",
    "MarkdownTableAddColumn",
    "MarkdownTableDeleteColumn",
    "MarkdownTableMoveColumnLeft",
    "MarkdownTableMoveColumnRight",
    "MarkdownTableToggleAlignment",
    "MarkdownTableEditCell",
  }) do
    h.assert_eq("editing command exists: " .. command, vim.fn.exists(":" .. command), 2)
  end
end)
