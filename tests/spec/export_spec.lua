local h = require("tests.helpers")

local function table_lines()
  return {
    "| Name | Link | Note |",
    "| --- | --- | --- |",
    '| Docs | [GitHub](https://github.com) | hello, "world" |',
  }
end

h.test("rendered cell copy is distinct from raw Source yank", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, min_col_width = 4, max_col_width = 18 })

  h.with_buffer(table_lines(), function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
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
    h.assert_true(
      "raw cell yank succeeds",
      require("markdown-table-wrap.cell_ops").yank(reader_bufnr, { silent = true })
    )
    h.assert_eq("raw yank keeps Markdown source", vim.fn.getreg('"'), "[GitHub](https://github.com)")

    h.assert_true("rendered cell copy succeeds", plugin.copy_rendered_cell({ clipboard = false, silent = true }))
    h.assert_eq("rendered copy returns visible label", vim.fn.getreg('"'), "GitHub")
    h.assert_deep_eq(
      "Source stays unchanged after copy",
      vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
      table_lines()
    )
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("Reader rendered cell copy joins wrapped segments", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, min_col_width = 4, max_col_width = 8, max_width_ratio = 1 })

  h.with_buffer({
    "| Name | Description |",
    "| --- | --- |",
    "| one | alpha beta gamma delta |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_width(0, 45)
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
    h.assert_true("wrapped rendered cell target exists", target ~= nil)
    vim.api.nvim_win_set_cursor(0, target)
    h.assert_true("Reader rendered cell copy succeeds", plugin.copy_rendered_cell({ clipboard = false, silent = true }))
    h.assert_eq("wrapped Reader copy uses semantic display text", vim.fn.getreg('"'), "alpha beta gamma delta")
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("rendered table copy includes borders and excludes raw Markdown syntax", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local render = require("markdown-table-wrap.render")
  plugin.setup({ auto_preview = false, min_col_width = 4, max_col_width = 18, max_width_ratio = 1 })

  h.with_buffer(table_lines(), function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_width(0, 80)
    local reader_bufnr = plugin.reader_preview()
    local state = reader.get_state(reader_bufnr)
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    h.assert_true("Reader table copy succeeds", plugin.copy_rendered_table({ clipboard = false, silent = true }))
    local copied = vim.fn.getreg('"')
    h.assert_true("table copy starts with rendered border", vim.startswith(copied, "╭"))
    h.assert_true("table copy includes visible label", copied:find("GitHub", 1, true) ~= nil)
    h.assert_false("table copy does not include raw URL", copied:find("https://github.com", 1, true) ~= nil)
    h.assert_eq("table copy matches Reader lines", copied, table.concat(state.segments[1].rendered.lines, "\n"))
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("CSV export escapes delimiters and quotes", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer(table_lines(), function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local ok, value = plugin.export_table({ format = "csv", clipboard = false, silent = true })
    h.assert_true("CSV export succeeds", ok)
    h.assert_eq("CSV has RFC-style escaping", value, 'Name,Link,Note\nDocs,GitHub,"hello, ""world"""')
    h.assert_eq("CSV is copied to unnamed register", vim.fn.getreg('"'), value)
  end)
end)

h.test("TSV export escapes control characters without changing table shape", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | `two\tthree` |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local ok, value = plugin.export_table({ format = "tsv", clipboard = false, silent = true })
    h.assert_true("TSV export succeeds", ok)
    h.assert_true("TSV keeps escaped tab in one field", value:find("two\\tthree", 1, true) ~= nil)
    h.assert_eq("TSV rows have one delimiter", select(2, value:gsub("\n", "")), 1)
  end)
end)

h.test("bang export includes every table while default export stays contextual", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
    "",
    "| C | D |",
    "| --- | --- |",
    "| three | four |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local _, one = plugin.export_table({ format = "tsv", clipboard = false, silent = true })
    local _, all = plugin.export_table({ format = "tsv", all = true, clipboard = false, silent = true })
    h.assert_true("contextual export has first table", one:find("one\ttwo", 1, true) ~= nil)
    h.assert_true("bang-style export has second table", all:find("three\tfour", 1, true) ~= nil)
    h.assert_true("multiple tables are separated", all:find("two\n\nC", 1, true) ~= nil)
  end)
end)

h.test("structured export refuses excess cells instead of dropping data", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two | excess |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    vim.fn.setreg('"', "sentinel", "v")
    h.assert_false(
      "overflow export is rejected",
      plugin.export_table({ format = "tsv", clipboard = false, silent = true })
    )
    h.assert_eq("overflow refusal preserves registers", vim.fn.getreg('"'), "sentinel")
  end)
end)

h.test("copy follows the clipboard option instead of always writing unnamedplus", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local original_clipboard = vim.o.clipboard
  local original_setreg = vim.fn.setreg
  local system_registers = {}
  vim.fn.setreg = function(register, value, kind)
    if register == "+" or register == "*" then
      system_registers[register] = { value = value, kind = kind }
      return 0
    end
    return original_setreg(register, value, kind)
  end

  local ok, err = pcall(function()
    h.with_buffer(table_lines(), function(buf)
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      vim.o.clipboard = ""
      system_registers["+"] = { value = "plus sentinel", kind = "v" }
      local copied = plugin.export_table({ format = "tsv", silent = true })
      h.assert_true("export without clipboard integration succeeds", copied)
      h.assert_eq("empty clipboard option leaves unnamedplus alone", system_registers["+"].value, "plus sentinel")

      vim.o.clipboard = "unnamedplus"
      local _, csv = plugin.export_table({ format = "csv", silent = true })
      h.assert_eq("unnamedplus receives the exported value", system_registers["+"].value, csv)
      h.assert_eq("unnamedplus uses a characterwise register", system_registers["+"].kind, "v")
    end)
  end)
  vim.fn.setreg = original_setreg
  vim.o.clipboard = original_clipboard
  if not ok then
    error(err, 0)
  end
end)

h.test("export actions are exposed as Plug mappings and commands", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  for _, plug in ipairs({
    "<Plug>(MarkdownTableWrapCopyCell)",
    "<Plug>(MarkdownTableWrapPutCell)",
    "<Plug>(MarkdownTableWrapCopyTable)",
    "<Plug>(MarkdownTableWrapExportTSV)",
    "<Plug>(MarkdownTableWrapExportCSV)",
  }) do
    h.assert_true("export Plug exists: " .. plug, vim.fn.maparg(plug, "n") ~= "")
  end
  for _, command in ipairs({
    "MarkdownTableYankCell",
    "MarkdownTablePutCell",
    "MarkdownTableYankTable",
    "MarkdownTableExport",
  }) do
    h.assert_eq("export command exists: " .. command, vim.fn.exists(":" .. command), 2)
  end
end)
