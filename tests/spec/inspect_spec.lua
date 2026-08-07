local h = require("tests.helpers")

local table_lines = {
  "| Name | Link |",
  "| --- | --- |",
  "| one | [target](target.md) |",
}

h.test("inspect and statusline expose coherent Source and Reader context", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, mappings = { reader = false } })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 12 })
    local source_context = plugin.get_state()
    local source_lines = require("markdown-table-wrap.inspect").format(source_context)
    h.assert_eq("Source context mode", source_context.mode, "source")
    h.assert_true("inspect includes Source mode", table.concat(source_lines, "\n"):find("Mode: Source", 1, true) ~= nil)
    h.assert_true("statusline includes table and cell", plugin.statusline():find("MTW Source T3:C2", 1, true) ~= nil)

    local reader_bufnr = plugin.reader_preview()
    local reader_context = plugin.get_state(reader_bufnr)
    h.assert_eq("Reader context resolves Source", reader_context.source_bufnr, source_bufnr)
    h.assert_true(
      "Reader inspect identifies the rendered view",
      table.concat(require("markdown-table-wrap.inspect").format(reader_context), "\n"):find("Mode: Reader", 1, true)
        ~= nil
    )
    h.assert_true(
      "Reader statusline identifies mode",
      plugin.statusline(reader_bufnr):find("MTW Reader", 1, true) ~= nil
    )

    local help_bufnr, help_winid = require("markdown-table-wrap.inspect").open_help(reader_context)
    local help = table.concat(vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false), "\n")
    h.assert_true("disabled mappings remain discoverable", help:find("local mappings: disabled", 1, true) ~= nil)
    h.assert_true("help always documents Source exit command", help:find(":MarkdownTableEditSource", 1, true) ~= nil)
    vim.api.nvim_win_close(help_winid, true)

    vim.api.nvim_set_current_buf(reader_bufnr)
    plugin.close_reader()
  end)
end)

h.test("health report covers context resolver mappings and coexistence", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, mappings = { reader = false } })
  local report = require("markdown-table-wrap.health").collect()
  local messages = {}
  for _, item in ipairs(report) do
    table.insert(messages, item.message)
  end
  local text = table.concat(messages, "\n")
  h.assert_true("health checks context", text:find("context", 1, true) ~= nil)
  h.assert_true("health checks resolver", text:find("Link resolver", 1, true) ~= nil)
  h.assert_true("health checks mappings", text:find("Reader mappings disabled", 1, true) ~= nil)
  h.assert_true("health checks renderer coexistence", text:find("render%-markdown.nvim") ~= nil)
end)

h.test("statusline stays empty outside configured Markdown sources", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  h.with_buffer({ "plain text" }, function(bufnr)
    vim.bo[bufnr].filetype = "text"
    h.assert_eq("unrelated buffer has no component", plugin.statusline(bufnr), "")
  end)
end)
