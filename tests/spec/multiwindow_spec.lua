local h = require("tests.helpers")

local table_lines = {
  "| Name | Description |",
  "| --- | --- |",
  "| one | content that wraps differently in narrow and wide Reader windows |",
}

local function delete_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

h.test("two Reader windows keep independent geometry and Source ownership", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local original_columns = vim.o.columns
  vim.o.columns = 120
  plugin.setup({ auto_preview = false, max_width_ratio = 1, min_col_width = 4, max_col_width = 50 })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local original_bufhidden = vim.bo[source_bufnr].bufhidden
    local first_win = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second_win, source_bufnr)
    vim.api.nvim_win_set_width(first_win, 38)

    vim.api.nvim_set_current_win(first_win)
    local first_reader = plugin.reader_preview()
    vim.api.nvim_set_current_win(second_win)
    local second_reader = plugin.reader_preview()

    local first_context = plugin.get_state(first_reader)
    local second_context = plugin.get_state(second_reader)
    h.assert_true("each window owns a different Reader", first_reader ~= second_reader)
    h.assert_eq("Readers share the same Source", first_context.source_bufnr, second_context.source_bufnr)
    h.assert_true("Reader contexts retain different windows", first_context.winid ~= second_context.winid)
    h.assert_true(
      "Reader contexts retain independent widths",
      first_context.window.width ~= second_context.window.width
    )
    h.assert_eq("Source remains safely hidden while Readers exist", vim.bo[source_bufnr].bufhidden, "hide")

    local refresh_calls = {}
    local original_refresh = reader.refresh
    reader.refresh = function(reader_bufnr)
      table.insert(refresh_calls, reader_bufnr)
      return true
    end
    h.assert_eq("targeted resize refreshes one Reader", reader.refresh_windows({ first_win }), 1)
    h.assert_deep_eq("targeted resize selects the matching Reader", refresh_calls, { first_reader })
    refresh_calls = {}
    h.assert_eq("global resize refreshes every visible Reader", reader.refresh_windows(), 2)
    table.sort(refresh_calls)
    local expected = { first_reader, second_reader }
    table.sort(expected)
    h.assert_deep_eq("global resize covers both Reader sessions", refresh_calls, expected)
    reader.refresh = original_refresh

    local resize_windows
    local original_refresh_windows = reader.refresh_windows
    reader.refresh_windows = function(winids)
      resize_windows = winids
      return 0
    end
    vim.api.nvim_exec_autocmds("VimResized", { modeline = false })
    reader.refresh_windows = original_refresh_windows
    local resized = {}
    for _, winid in ipairs(resize_windows or {}) do
      resized[winid] = true
    end
    h.assert_true("VimResized fans out to the first Reader window", resized[first_win])
    h.assert_true("VimResized fans out to the second Reader window", resized[second_win])

    vim.api.nvim_set_current_win(first_win)
    plugin.close_reader()
    h.assert_true("closing first Reader leaves second active", reader.is_reader(second_reader))
    h.assert_eq("Source hide ownership remains with second Reader", vim.bo[source_bufnr].bufhidden, "hide")

    vim.api.nvim_set_current_win(second_win)
    plugin.close_reader()
    h.assert_eq("last Reader restores original Source bufhidden", vim.bo[source_bufnr].bufhidden, original_bufhidden)
    plugin.state.paused_buffers[source_bufnr] = nil
    vim.api.nvim_win_close(second_win, true)
  end)

  vim.o.columns = original_columns
end)

h.test("Source edits refresh dependent Readers without replacing the Source window", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local source_win = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local reader_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(reader_win, source_bufnr)
    local reader_bufnr = plugin.reader_preview()

    vim.api.nvim_buf_set_lines(source_bufnr, 2, 3, false, { "| updated | changed from the Source window |" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = source_bufnr, modeline = false })
    vim.wait(100, function()
      local rendered = table.concat(vim.api.nvim_buf_get_lines(reader_bufnr, 0, -1, false), "\n")
      return rendered:find("updated", 1, true) ~= nil
    end, 5)

    h.assert_eq("Source window remains Source", vim.api.nvim_win_get_buf(source_win), source_bufnr)
    h.assert_eq("Reader window remains Reader", vim.api.nvim_win_get_buf(reader_win), reader_bufnr)
    h.assert_true("dependent Reader remains active", reader.is_reader(reader_bufnr))
    h.assert_true(
      "dependent Reader receives Source changes",
      table.concat(vim.api.nvim_buf_get_lines(reader_bufnr, 0, -1, false), "\n"):find("updated", 1, true) ~= nil
    )

    vim.api.nvim_set_current_win(reader_win)
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
    vim.api.nvim_win_close(reader_win, true)
  end)
end)

h.test("Reader alternate-buffer action preserves the Source alternate target", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  local alternate = vim.api.nvim_create_buf(true, false)
  local source = vim.api.nvim_create_buf(true, false)
  vim.bo[alternate].swapfile = false
  vim.bo[source].swapfile = false
  vim.api.nvim_buf_set_lines(alternate, 0, -1, false, { "alternate" })
  vim.api.nvim_buf_set_lines(source, 0, -1, false, table_lines)
  vim.bo[alternate].modified = false
  vim.bo[source].modified = false
  vim.bo[source].filetype = "markdown"
  vim.api.nvim_set_current_buf(alternate)
  vim.api.nvim_set_current_buf(source)

  local reader_bufnr = plugin.reader_preview()
  h.assert_true("alternate action succeeds", require("markdown-table-wrap.actions").run("alternate_buffer"))
  h.assert_eq("alternate action skips disposable Reader", vim.api.nvim_get_current_buf(), alternate)
  h.assert_false("alternate action cleans Reader", require("markdown-table-wrap.reader").is_reader(reader_bufnr))

  delete_buffer(source)
  delete_buffer(alternate)
end)
