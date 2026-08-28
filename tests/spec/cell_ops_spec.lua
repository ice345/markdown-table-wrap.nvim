local h = require("tests.helpers")

local function source_lines()
  return {
    "A paragraph outside the table.",
    "",
    "| Name | Link | Notes |",
    "| --- | --- | --- |",
    "| one | [GitHub documentation portal](https://github.com) | a deliberately long note that wraps across several Reader lines |",
  }
end

local function delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function open_reader(width)
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 1,
    min_col_width = 4,
    max_col_width = 18,
    row_separator = true,
  })
  local source_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[source_bufnr].buftype = "nofile"
  vim.bo[source_bufnr].swapfile = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, source_lines())
  vim.api.nvim_set_current_buf(source_bufnr)
  vim.api.nvim_win_set_width(0, width or 72)
  local reader_bufnr = plugin.reader_preview()
  return plugin, source_bufnr, reader_bufnr
end

local function position_on_cell(reader_bufnr, source_lnum, column_index)
  local reader = require("markdown-table-wrap.reader")
  local state = reader.get_state(reader_bufnr)
  for row, line_object in ipairs(state.line_objects or {}) do
    for _, cell in ipairs(type(line_object) == "table" and line_object.cells or {}) do
      if cell.source_span and cell.source_span.start_lnum == source_lnum and cell.column_index == column_index then
        vim.api.nvim_win_set_cursor(0, { row, cell.start_col })
        return reader.cell_at_cursor(reader_bufnr)
      end
    end
  end
  return nil
end

local function close_and_delete(plugin, source_bufnr)
  if vim.api.nvim_get_current_buf() ~= source_bufnr then
    plugin.close_reader()
  end
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end

h.test("yic copies the original Markdown source of a wrapped cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  local cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("link cell is found in Reader", cell ~= nil)
  h.assert_true("link cell has multiple rendered segments", cell.render_end_row > cell.render_start_row)

  local cell_ops = require("markdown-table-wrap.cell_ops")
  h.assert_true("yic succeeds", cell_ops.yank(reader_bufnr))
  h.assert_eq("yic uses raw source", vim.fn.getreg('"'), "[GitHub documentation portal](https://github.com)")
  h.assert_eq(
    "yic populates the yank register",
    vim.fn.getreg("0"),
    "[GitHub documentation portal](https://github.com)"
  )
  vim.api.nvim_win_set_cursor(0, { cell.render_end_row, cell.render_start_col })
  h.assert_true("yic works from a wrapped continuation line", cell_ops.yank(reader_bufnr))
  h.assert_eq("wrapped-line yic remains raw", vim.fn.getreg('"'), "[GitHub documentation portal](https://github.com)")

  close_and_delete(plugin, source_bufnr)
end)

h.test("cell operations refresh a stale Reader projection before resolving", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("initial cell is found", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.api.nvim_buf_set_lines(source_bufnr, 4, 5, false, {
    "| one | [updated source](https://example.com) | a deliberately long note that wraps across several Reader lines |",
  })
  h.assert_true("stale Reader yic succeeds", require("markdown-table-wrap.cell_ops").yank(reader_bufnr))
  h.assert_eq("stale Reader resolves new Source span", vim.fn.getreg('"'), "[updated source](https://example.com)")
  close_and_delete(plugin, source_bufnr)
end)

h.test("vic selects every rendered segment of one logical cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  local cell = position_on_cell(reader_bufnr, 5, 3)
  h.assert_true("wrapped note cell is found", cell ~= nil)

  h.assert_true("vic succeeds", require("markdown-table-wrap.cell_ops").visual(reader_bufnr))
  h.assert_eq("vic uses blockwise Visual mode", vim.api.nvim_get_mode().mode, "\22")
  local marks = vim.api.nvim_buf_get_extmarks(
    reader_bufnr,
    require("markdown-table-wrap.reader").visual_namespace(),
    0,
    -1,
    { details = true }
  )
  h.assert_eq("vic covers each wrapped cell line", #marks, cell.render_end_row - cell.render_start_row + 1)
  for _, mark in ipairs(marks) do
    h.assert_eq("vic stays inside the cell rectangle", mark[3], cell.render_start_col)
    h.assert_eq("vic overlay uses Visual highlight", mark[4].virt_text[1][2], "Visual")
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  h.assert_eq(
    "vic visual overlay clears after leaving Visual",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, require("markdown-table-wrap.reader").visual_namespace(), 0, -1, {}),
    0
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("native v and V get visible Reader selection overlays inside tables", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("cell is found for native visual selection", cell ~= nil)

  vim.cmd("normal! v")
  require("markdown-table-wrap.reader").update_visual_selection(reader_bufnr)
  local namespace = require("markdown-table-wrap.reader").visual_namespace()
  h.assert_true(
    "native v installs a selection overlay",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, namespace, 0, -1, {}) > 0
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  position_on_cell(reader_bufnr, 5, 2)
  vim.cmd("normal! V")
  require("markdown-table-wrap.reader").update_visual_selection(reader_bufnr)
  h.assert_true(
    "native V installs a selection overlay",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, namespace, 0, -1, {}) > 0
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  close_and_delete(plugin, source_bufnr)
end)

h.test("dic clears only the selected cell and preserves table structure", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  h.assert_true("dic succeeds", require("markdown-table-wrap.cell_ops").delete(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_eq(
    "dic leaves the row and neighboring cells",
    line,
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_false("dic removes only cell content", line:find("GitHub", 1, true) ~= nil)
  h.assert_eq(
    "dic places deleted source in unnamed register",
    vim.fn.getreg('"'),
    "[GitHub documentation portal](https://github.com)"
  )
  h.assert_true("dic keeps Reader active", require("markdown-table-wrap.reader").is_reader(reader_bufnr))
  close_and_delete(plugin, source_bufnr)
end)

h.test("cip inserts register text into the exact Source cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "**new label**")
  h.assert_true("cip succeeds", require("markdown-table-wrap.cell_ops").put(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_eq(
    "cip preserves neighboring cells and pipes",
    line,
    "| one | **new label** | a deliberately long note that wraps across several Reader lines |"
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("cip keeps a multiline register on the same table row", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for multiline put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "first\nsecond")
  h.assert_true("multiline cip succeeds", require("markdown-table-wrap.cell_ops").put(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_true("multiline cip flattens newlines", line:find("first second", 1, true) ~= nil)
  h.assert_eq("multiline cip keeps the row pipe", line:sub(-1), "|")
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell mutations respect a read-only Source buffer", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for read-only guard", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.bo[source_bufnr].readonly = true
  h.assert_false("read-only delete is rejected", require("markdown-table-wrap.cell_ops").delete(reader_bufnr))
  h.assert_true(
    "read-only Source remains unchanged",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]:find("GitHub", 1, true) ~= nil
  )
  vim.bo[source_bufnr].readonly = false
  close_and_delete(plugin, source_bufnr)
end)

h.test("cic clears the Source cell and enters Source Insert mode", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for change", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  h.assert_true("cic succeeds", require("markdown-table-wrap.cell_ops").change(reader_bufnr))
  h.assert_eq("cic returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
  h.assert_eq(
    "cic clears only cell content",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_false("cic keeps normal Reader re-entry unpaused", plugin.state.paused_buffers[source_bufnr] == true)
  -- Headless Neovim cannot enter an interactive Insert mode, but the action
  -- still requests Source Insert in a real UI via :startinsert.
  close_and_delete(plugin, source_bufnr)
end)

h.test("c delegates to the captured Source mapping outside a cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local calls = 0
  vim.keymap.set("n", "c", function()
    calls = calls + 1
  end, { buffer = source_bufnr })
  require("markdown-table-wrap.reader").reconfigure(reader_bufnr, plugin.get_buffer_config(source_bufnr))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  h.assert_true("c fallback succeeds", require("markdown-table-wrap.cell_ops").change_or_fallback(reader_bufnr))
  h.assert_eq("c fallback runs once", calls, 1)
  h.assert_eq("c fallback runs in Source", vim.api.nvim_get_current_buf(), source_bufnr)
  h.assert_false("c fallback closes Reader", require("markdown-table-wrap.reader").is_reader(reader_bufnr))
  close_and_delete(plugin, source_bufnr)
end)

h.test("Reader cell mappings are configurable and can be disabled", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local mappings = vim.api.nvim_buf_get_keymap(reader_bufnr, "n")
  local seen = {}
  for _, mapping in ipairs(mappings) do
    seen[mapping.lhs] = true
  end
  h.assert_true("default yic mapping is installed", seen.yic)
  h.assert_true("default vic mapping is installed", seen.vic)
  h.assert_true("default dic mapping is installed", seen.dic)
  h.assert_true("default cic mapping is installed", seen.cic)
  h.assert_true("default cip mapping is installed", seen.cip)
  h.assert_true("default c mapping is installed", seen.c)
  position_on_cell(reader_bufnr, 5, 2)
  vim.cmd("normal yic")
  h.assert_eq(
    "mapped yic copies the raw Source cell",
    vim.fn.getreg('"'),
    "[GitHub documentation portal](https://github.com)"
  )
  close_and_delete(plugin, source_bufnr)

  plugin, source_bufnr, reader_bufnr = open_reader(72)
  plugin.setup({ auto_preview = false, mappings = { reader = { cell = false } } })
  mappings = vim.api.nvim_buf_get_keymap(reader_bufnr, "n")
  seen = {}
  for _, mapping in ipairs(mappings) do
    seen[mapping.lhs] = true
  end
  h.assert_false("cell mappings can be disabled", seen.yic or seen.vic or seen.dic or seen.cic or seen.cip or seen.c)
  plugin.close_reader()
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end)
