local h = require("tests.helpers")

local table_lines = {
  "| A | B |",
  "| --- | --- |",
  "| one | two |",
}

h.test("active context resolves Source Inline and Reader to one Source", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")
  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"

    local source = plugin.get_state(source_bufnr)
    h.assert_eq("Source context mode", source.mode, "source")
    h.assert_eq("Source context identity", source.source_bufnr, source_bufnr)
    h.assert_eq("Source is its own view", source.view_bufnr, source_bufnr)

    h.assert_true("Inline opens", plugin.toggle_inline())
    local inline_context = plugin.get_state(source_bufnr)
    h.assert_eq("Inline context mode", inline_context.mode, "inline")
    h.assert_eq("Inline resolves canonical Source", inline_context.source_bufnr, source_bufnr)
    h.assert_true("Inline context includes layout state", inline_context.inline ~= nil)
    inline.clear(source_bufnr)
    plugin.state.buffer_modes[source_bufnr] = "reader"

    local reader_bufnr = plugin.reader_preview()
    local reader_context = plugin.get_state(reader_bufnr)
    h.assert_true("Reader opens", reader.is_reader(reader_bufnr))
    h.assert_eq("Reader context mode", reader_context.mode, "reader")
    h.assert_eq("Reader resolves canonical Source", reader_context.source_bufnr, source_bufnr)
    h.assert_eq("public Source resolver handles Reader", plugin.resolve_source_buffer(reader_bufnr), source_bufnr)
    h.assert_true("Reader context exposes independent window geometry", reader_context.window.width ~= nil)

    local reader_state = reader.get_state(reader_bufnr)
    local second_cell_cursor = nil
    for row, line_object in ipairs(reader_state.line_objects) do
      if reader_state.reader_to_source[row] == 3 and line_object.cells and line_object.cells[2] then
        second_cell_cursor = { row, line_object.cells[2].start_col + 1 }
        break
      end
    end
    vim.api.nvim_win_set_cursor(0, second_cell_cursor)
    local second_cell_context = plugin.get_state(reader_bufnr)
    h.assert_eq("Reader cursor maps back to the rendered Source cell", second_cell_context.cell.index, 2)

    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("view events include safe Source and Reader identities", function()
  local plugin = require("markdown-table-wrap")
  local events = {}
  local group = vim.api.nvim_create_augroup("MarkdownTableWrapContextSpec", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MarkdownTableWrap*",
    callback = function(args)
      table.insert(events, { match = args.match, data = args.data or {} })
    end,
  })

  plugin.setup({ auto_preview = false, preview_mode = "reader" })
  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local reader_bufnr = plugin.reader_preview()
    plugin.close_reader()

    local seen = {}
    for _, event in ipairs(events) do
      seen[event.match] = event.data
    end

    h.assert_eq("ReaderEnter identifies Source", seen.MarkdownTableWrapReaderEnter.source_bufnr, source_bufnr)
    h.assert_eq("ReaderEnter identifies Reader", seen.MarkdownTableWrapReaderEnter.view_bufnr, reader_bufnr)
    h.assert_eq("ReaderLeave returns to Source", seen.MarkdownTableWrapReaderLeave.mode, "source")
    h.assert_true("render completion event emitted", seen.MarkdownTableWrapRendered ~= nil)
    plugin.state.paused_buffers[source_bufnr] = nil
  end)

  pcall(vim.api.nvim_del_augroup_by_id, group)
end)

h.test("the same Source has window-local context geometry", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local first_win = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second_win, source_bufnr)

    local first = require("markdown-table-wrap.context").resolve({ bufnr = source_bufnr, winid = first_win })
    local second = require("markdown-table-wrap.context").resolve({ bufnr = source_bufnr, winid = second_win })
    h.assert_eq("windows share canonical Source", first.source_bufnr, second.source_bufnr)
    h.assert_true("contexts retain distinct window identities", first.winid ~= second.winid)

    vim.api.nvim_win_close(second_win, true)
  end)
end)
