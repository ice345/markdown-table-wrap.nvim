local h = require("tests.helpers")

h.test("system render chain only conceals detected table range", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    row_separator = true,
    inline_viewport_scrolling = false,
  })

  h.with_buffer({
    "pipe prose | should stay visible",
    "| A | B |",
    "| --- | --- |",
    "| `code` | [link](url)<br>**bold** |",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local concealed_rows = {}
    local styled = {}

    for _, mark in ipairs(marks) do
      local row = mark[2]
      local details = mark[4] or {}
      if details.conceal == "" then
        concealed_rows[row] = true
      end
      for _, chunk in ipairs(details.virt_text or {}) do
        styled[chunk[2]] = true
      end
      for _, virt_line in ipairs(details.virt_lines or {}) do
        for _, chunk in ipairs(virt_line) do
          styled[chunk[2]] = true
        end
      end
    end

    h.assert_false("adjacent prose is not concealed", concealed_rows[0])
    h.assert_true("header concealed", concealed_rows[1])
    h.assert_true("separator concealed", concealed_rows[2])
    h.assert_true("row concealed", concealed_rows[3])
    h.assert_true("code styled through chain", styled.MarkdownTableWrapCode)
    h.assert_true("link styled through chain", styled.MarkdownTableWrapLink)
    h.assert_true("bold styled through chain", styled.MarkdownTableWrapBold)

    inline.clear(buf)
  end)
end)

h.test("plugin loader does not override manual setup", function()
  local plugin = require("markdown-table-wrap")
  local plugin_file = vim.fn.fnamemodify("plugin/markdown-table-wrap.lua", ":p")

  vim.g.loaded_markdown_table_wrap = nil
  plugin.state.did_setup = false

  plugin.setup({
    table_border = "single",
    row_separator = false,
    highlight_preset = "default",
    inline_viewport_scrolling = false,
  })

  dofile(plugin_file)

  h.assert_eq("manual table_border preserved", plugin.config.table_border, "single")
  h.assert_false("manual row_separator preserved", plugin.config.row_separator)
  h.assert_eq("manual highlight_preset preserved", plugin.config.highlight_preset, "default")
  h.assert_false("manual viewport preference preserved", plugin.config.inline_viewport_scrolling)
end)

h.test("extra_filetypes renders in configured filetype", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    extra_filetypes = { "text" },
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| foo | bar |",
  }, function(buf)
    vim.bo[buf].filetype = "text"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local rendered = #marks > 0

    h.assert_true("table rendered in extra_filetype text", rendered)

    inline.clear(buf)
  end)
end)

h.test("R Markdown filetypes render without extra configuration", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = false,
  })

  for _, filetype in ipairs({ "rmd", "rmarkdown" }) do
    h.with_buffer({
      "| A | B |",
      "| --- | --- |",
      "| foo | bar |",
    }, function(buf)
      vim.bo[buf].filetype = filetype
      plugin.refresh_auto({ force = true })
      h.assert_true(filetype .. " table renders", inline.is_active(buf))
      inline.clear(buf)
    end)
  end
end)

h.test("non-configured filetypes are ignored", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    extra_filetypes = { "text" },
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| foo | bar |",
  }, function(buf)
    vim.bo[buf].filetype = "python"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local rendered = #marks > 0

    h.assert_false("table not rendered in non-configured filetype", rendered)

    inline.clear(buf)
  end)
end)

h.test("public preview commands switch views from the user's current context", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local parser = require("markdown-table-wrap.parser")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ preview_mode = "reader", debounce_ms = 0, min_col_width = 4, max_col_width = 12 })

  local original_notify = vim.notify
  local messages = {}
  vim.notify = function(message)
    table.insert(messages, tostring(message))
  end
  local ok, err = pcall(function()
    h.with_buffer({
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
    }, function(source_bufnr)
      vim.bo[source_bufnr].filetype = "markdown"
      local table_info = parser.parse_at_cursor(source_bufnr, 3)
      plugin.refresh_auto()
      local reader_bufnr = vim.api.nvim_get_current_buf()
      h.assert_true("default automatic flow starts in Reader", reader.is_reader(reader_bufnr))
      h.assert_true(
        "Reader focuses the second body cell",
        reader.focus_source_cell(reader_bufnr, 3, 2, table_info.id, 1)
      )

      vim.cmd("MarkdownTableFloatPreview")
      h.assert_eq("Float command keeps the canonical Source", plugin.state.float_source_bufnr, source_bufnr)
      h.assert_eq("Float command makes its view current", vim.api.nvim_get_current_buf(), plugin.state.buf)
      local float_context = plugin.get_state(plugin.state.buf)
      h.assert_eq("Reader-to-Float keeps the logical row", float_context.cell.row_index, 1)
      h.assert_eq("Reader-to-Float keeps the logical column", float_context.cell.index, 2)

      vim.cmd("MarkdownTableReader")
      h.assert_true("Reader command returns from Float", reader.is_reader(0))
      vim.cmd("MarkdownTableInlinePreview")
      h.assert_eq("Inline command returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
      h.assert_true("Reader-to-Inline renders the Source buffer", inline.is_active(source_bufnr))
      plugin.close_preview()
      plugin.state.paused_buffers[source_bufnr] = nil
    end)
  end)
  vim.notify = original_notify
  if not ok then
    error(err, 0)
  end
  h.assert_false(
    "view switches emit no false filetype warning",
    table.concat(messages, "\n"):find("only available in Markdown buffers", 1, true) ~= nil
  )
end)

h.test("Reader leader mapping keeps the requested Float after auto-preview debounce", function()
  local plugin = require("markdown-table-wrap")
  local parser = require("markdown-table-wrap.parser")
  local reader = require("markdown-table-wrap.reader")
  local previous_leader = vim.g.mapleader
  vim.g.mapleader = " "
  vim.keymap.set("n", "<leader>mf", "<cmd>MarkdownTableFloatPreview<cr>", {
    desc = "Float Markdown table preview",
  })
  plugin.setup({ preview_mode = "reader", debounce_ms = 20, min_col_width = 4, max_col_width = 12 })

  local ok, err = pcall(function()
    h.with_buffer({
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
    }, function(source_bufnr)
      vim.bo[source_bufnr].filetype = "markdown"
      local table_info = parser.parse_at_cursor(source_bufnr, 3)
      plugin.refresh_auto()
      local reader_bufnr = vim.api.nvim_get_current_buf()
      h.assert_true("automatic preview opens Reader before the keypress", reader.is_reader(reader_bufnr))
      h.assert_true(
        "Reader focuses the second body cell before the keypress",
        reader.focus_source_cell(reader_bufnr, 3, 2, table_info.id, 1)
      )

      local keys = vim.api.nvim_replace_termcodes("<leader>mf", true, false, true)
      vim.fn.feedkeys(keys, "xt")
      h.assert_eq("leader mapping immediately opens Float", vim.api.nvim_get_current_buf(), plugin.state.buf)

      vim.wait(100)
      h.assert_true(
        "Float window survives the stale Reader debounce",
        plugin.state.win ~= nil and vim.api.nvim_win_is_valid(plugin.state.win)
      )
      h.assert_eq("Float remains current after debounce", vim.api.nvim_get_current_buf(), plugin.state.buf)
      h.assert_eq("mapped Float retains Source ownership", plugin.state.float_source_bufnr, source_bufnr)
      local float_context = plugin.get_state(plugin.state.buf)
      h.assert_eq("mapped Float keeps the logical row", float_context.cell.row_index, 1)
      h.assert_eq("mapped Float keeps the logical column", float_context.cell.index, 2)

      plugin.close_preview()
      plugin.state.paused_buffers[source_bufnr] = nil
    end)
  end)

  pcall(vim.keymap.del, "n", "<leader>mf")
  vim.g.mapleader = previous_leader
  if not ok then
    error(err, 0)
  end
end)

h.test("Float q restores the Source Reader or Inline origin", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local parser = require("markdown-table-wrap.parser")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "reader", min_col_width = 4, max_col_width = 12 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local table_info = parser.parse_at_cursor(source_bufnr, 3)
    vim.api.nvim_win_set_cursor(0, { 3, 9 })

    plugin.float_preview()
    vim.fn.feedkeys("q", "xt")
    h.assert_eq("Source-origin Float q returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_eq("Source-origin Float q clears the Float buffer state", plugin.state.buf, nil)
    h.assert_eq("Source-origin Float q clears the Float window state", plugin.state.win, nil)

    local reader_bufnr = plugin.reader_preview()
    h.assert_true("Reader opens before its Float", reader.is_reader(reader_bufnr))
    h.assert_true(
      "Reader origin focuses the second body cell",
      reader.focus_source_cell(reader_bufnr, 3, 2, table_info.id, 1)
    )
    plugin.float_preview()
    vim.fn.feedkeys("q", "xt")
    h.assert_true("Reader-origin Float q restores Reader", reader.is_reader(0))
    local restored_context = plugin.get_state()
    h.assert_eq("restored Reader keeps the logical row", restored_context.cell.row_index, 1)
    h.assert_eq("restored Reader keeps the logical column", restored_context.cell.index, 2)

    plugin.float_preview()
    vim.cmd("MarkdownTableTogglePreview")
    h.assert_true("Float toggle restores its Reader origin", reader.is_reader(0))
    reader.close(0)

    plugin.inline_preview()
    h.assert_true("Inline opens before its Float", inline.is_active(source_bufnr))
    plugin.float_preview()
    vim.fn.feedkeys("q", "xt")
    h.assert_eq("Inline-origin Float q returns to Source buffer", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_true("Inline-origin Float q restores Inline", inline.is_active(source_bufnr))
    plugin.close_preview()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("Float refresh preserves its Reader return target", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "reader", min_col_width = 4, max_col_width = 12 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    plugin.reader_preview()
    plugin.float_preview()
    vim.cmd("MarkdownTableRefresh")
    h.assert_eq("refresh keeps Float current", vim.api.nvim_get_current_buf(), plugin.state.buf)
    vim.fn.feedkeys("q", "xt")
    h.assert_true("refreshed Float q still restores Reader", reader.is_reader(0))
    reader.close(0)
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("auto-preview and status commands resolve Reader and Float to Source", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", min_col_width = 4, max_col_width = 12 })

  local original_notify = vim.notify
  local messages = {}
  vim.notify = function(message)
    table.insert(messages, tostring(message))
  end
  local ok, err = pcall(function()
    h.with_buffer({
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
    }, function(source_bufnr)
      vim.bo[source_bufnr].filetype = "markdown"
      plugin.refresh_auto()
      h.assert_true("automatic preview starts in Reader", reader.is_reader(0))

      local first_reader_bufnr = vim.api.nvim_get_current_buf()
      vim.cmd("MarkdownTableToggleInlineViewport")
      h.assert_true("Reader viewport toggle updates Source", plugin.state.inline_viewports[source_bufnr] == true)
      h.assert_eq(
        "Reader viewport toggle does not key scratch state",
        plugin.state.inline_viewports[first_reader_bufnr],
        nil
      )
      h.assert_true("Reader viewport toggle keeps Reader", reader.is_reader(0))

      vim.cmd("MarkdownTableFloatPreview")
      vim.cmd("MarkdownTableStatus")
      h.assert_true(
        "Float status reports its resolved view",
        (messages[#messages] or ""):find("view=float", 1, true) ~= nil
      )
      local float_bufnr = vim.api.nvim_get_current_buf()
      vim.cmd("MarkdownTableToggleInlineViewport")
      h.assert_eq("Float viewport toggle updates Source", plugin.state.inline_viewports[source_bufnr], false)
      h.assert_eq("Float viewport toggle does not key scratch state", plugin.state.inline_viewports[float_bufnr], nil)
      h.assert_eq("Float viewport toggle keeps Float", vim.api.nvim_get_current_buf(), float_bufnr)
      vim.cmd("MarkdownTableToggleAutoPreview")
      h.assert_eq("Float auto toggle returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
      h.assert_eq("Float auto toggle disables the Source policy", plugin.state.auto_buffers[source_bufnr], false)
      h.assert_true("Float auto toggle pauses Source", plugin.state.paused_buffers[source_bufnr] == true)

      vim.cmd("MarkdownTableEnableAutoPreview")
      h.assert_eq("Source enable updates the Source policy", plugin.state.auto_buffers[source_bufnr], true)
      h.assert_true("Source enable reopens configured Reader", reader.is_reader(0))
      vim.cmd("MarkdownTableDisableAutoPreview")
      h.assert_eq("Reader disable returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
      h.assert_eq("Reader disable updates the Source policy", plugin.state.auto_buffers[source_bufnr], false)
      h.assert_true("Reader disable leaves Source paused", plugin.state.paused_buffers[source_bufnr] == true)

      plugin.float_preview()
      vim.cmd("MarkdownTableEnableAutoPreview")
      h.assert_eq("Float enable updates the Source policy", plugin.state.auto_buffers[source_bufnr], true)
      h.assert_eq("Float enable keeps the explicit Float", vim.api.nvim_get_current_buf(), plugin.state.buf)
      h.assert_eq("Float enable clears the Source pause", plugin.state.paused_buffers[source_bufnr], nil)
      vim.fn.feedkeys("q", "xt")
      h.assert_eq("enabled Source-origin Float q returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
      h.assert_eq("Float enable remains unpaused after q", plugin.state.paused_buffers[source_bufnr], nil)
      plugin.disable_auto_preview()
    end)
  end)
  vim.notify = original_notify
  if not ok then
    error(err, 0)
  end
end)
