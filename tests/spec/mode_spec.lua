local h = require("tests.helpers")

h.test("toggle inline switches between source and inline rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    h.assert_true("inline mode enabled", plugin.toggle_inline())
    h.assert_true("inline rendering is active", inline.is_active(buf))
    h.assert_eq("mode switches to inline", plugin.config.preview_mode, "inline")

    h.assert_false("inline mode disabled", plugin.toggle_inline())
    h.assert_false("inline rendering is cleared", inline.is_active(buf))
    h.assert_true("source mode pauses automatic rendering", plugin.state.paused_buffers[buf])
  end)
end)

h.test("toggle inline leaves Reader and renders the source buffer", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local reader_bufnr = plugin.reader_preview()
    h.assert_true("reader opens first", reader.is_reader(reader_bufnr))

    h.assert_true("inline toggle succeeds from Reader", plugin.toggle_inline())
    h.assert_eq("source buffer becomes current", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_true("inline rendering replaces Reader", inline.is_active(source_bufnr))
    h.assert_false("Reader is closed", reader.is_reader(vim.api.nvim_get_current_buf()))

    inline.clear(source_bufnr)
    plugin.state.inline_buf = nil
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)
