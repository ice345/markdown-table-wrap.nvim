local h = require("tests.helpers")

h.test("reader is the default preview mode", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  h.assert_eq("default preview mode", plugin.config.preview_mode, "reader")
end)

h.test("reader replaces source tables without modifying Markdown", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 0.9,
    min_col_width = 8,
    max_col_width = 50,
    fit_to_window = true,
  })

  local source_lines = {
    "A normal Markdown paragraph stays in the reader and can use native wrap.",
    "",
    "| Article | Read now | Workflow | Later |",
    "|---|---|---|---|",
    "| [eBPF verifier](https://docs.kernel.org/bpf/verifier.html) | register calling convention | bpf() load, JIT/attach | Week 5 state/bounds/pruning/log |",
    "",
    "Paragraph after the table.",
  }

  h.with_buffer(source_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.wo.wrap = true
    vim.api.nvim_win_set_width(0, 80)

    local reader_bufnr = plugin.reader_preview()
    h.assert_true("reader buffer created", reader_bufnr ~= nil and reader_bufnr ~= source_bufnr)
    h.assert_true("reader buffer active", reader.is_reader(reader_bufnr))
    h.assert_eq("reader is current buffer", vim.api.nvim_get_current_buf(), reader_bufnr)
    h.assert_false("reader is not modifiable", vim.bo[reader_bufnr].modifiable)
    h.assert_true("reader keeps native prose wrap", vim.wo.wrap)

    local visual_is_buffer_mapped = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(reader_bufnr, "n")) do
      if mapping.lhs == "V" or mapping.lhs == "v" or mapping.lhs == "<C-V>" then
        visual_is_buffer_mapped = true
      end
    end
    h.assert_false("Visual selection stays in the real reader buffer", visual_is_buffer_mapped)

    local rendered_lines = vim.api.nvim_buf_get_lines(reader_bufnr, 0, -1, false)
    local rendered_text = table.concat(rendered_lines, "\n")
    h.assert_true("reader contains Unicode table", rendered_text:find("╭", 1, true) ~= nil)
    h.assert_true("reader contains rendered link label", rendered_text:find("eBPF verifier", 1, true) ~= nil)
    h.assert_false("reader omits raw link URL", rendered_text:find("https://docs.kernel.org", 1, true) ~= nil)

    local table_top = nil
    for index, line in ipairs(rendered_lines) do
      if line:match("^╭") then
        table_top = index
        break
      end
    end
    h.assert_true("reader table top exists", table_top ~= nil)
    vim.api.nvim_win_set_cursor(0, { table_top, 0 })
    vim.cmd("normal! Vjy")
    h.assert_eq("Visual yank stays in reader", vim.api.nvim_get_current_buf(), reader_bufnr)
    h.assert_true("Visual yank copies rendered lines", vim.fn.getreg('"'):find("╭", 1, true) ~= nil)

    for index, line in ipairs(rendered_lines) do
      if line:match("^[╭├╰│]") then
        h.assert_true("reader table line fits window " .. index, vim.api.nvim_strwidth(line) <= 72)
      end
      if line:match("^│") then
        local _, borders = line:gsub("│", "")
        h.assert_eq("reader content line has only column borders " .. index, borders, 5)
      end
    end

    h.assert_true(
      "source Markdown is unchanged",
      vim.deep_equal(vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), source_lines)
    )

    h.assert_true("reader closes to source", plugin.close_reader())
    h.assert_eq("source restored", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_true("source wrap restored", vim.wo.wrap)
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("reader toggle switches between rendered and source views", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")

  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"

    local reader_bufnr = plugin.toggle_reader()
    h.assert_true("toggle opens reader", reader.is_reader(reader_bufnr))
    h.assert_true("toggle closes reader", plugin.toggle_reader())
    h.assert_eq("toggle restores source", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_true("closed reader pauses source", plugin.state.paused_buffers[source_bufnr])

    local reopened = plugin.toggle_reader()
    h.assert_true("toggle reopens reader", reader.is_reader(reopened))
    h.assert_eq("reopening clears pause", plugin.state.paused_buffers[source_bufnr], nil)
    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("reader gx opens table link metadata", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 1,
    min_col_width = 4,
    max_col_width = 40,
  })

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [YouTube](https://youtube.com/watch) |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local reader_bufnr = plugin.reader_preview()
    local built = reader._build(source_bufnr, plugin.config)
    local target = nil

    for row, line_object in ipairs(built.line_objects) do
      for _, chunk in ipairs(type(line_object) == "table" and line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url then
          target = { row, chunk.start_col }
          break
        end
      end
      if target then
        break
      end
    end

    h.assert_true("reader link target exists", target ~= nil)
    vim.api.nvim_win_set_cursor(0, target)
    h.assert_true("reader opens link", reader.open_link(reader_bufnr))
    h.assert_eq("reader opens original URL", opened, "https://youtube.com/watch")

    plugin.close_reader()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)

  vim.ui.open = original_open
end)

h.test("reader source editing restores the mapped source line", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 1,
    min_col_width = 4,
    max_col_width = 16,
  })

  h.with_buffer({
    "Before",
    "| Name | Description |",
    "| --- | --- |",
    "| Row | content that wraps across several rendered rows |",
    "After",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_width(0, 48)
    local reader_bufnr = plugin.reader_preview()
    local built = reader._build(source_bufnr, plugin.config)
    local reader_lnum = built.source_to_reader[4]

    h.assert_true("wrapped source row is mapped", reader_lnum ~= nil)
    vim.api.nvim_win_set_cursor(0, { reader_lnum, 0 })
    h.assert_true("reader edit returns to source", reader.edit(reader_bufnr, nil, true))
    h.assert_eq("reader restores source buffer", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_eq("reader restores source row", vim.api.nvim_win_get_cursor(0)[1], 4)
    h.assert_true("explicit source editing pauses reader", plugin.state.paused_buffers[source_bufnr])
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("reader safely hides an unsaved source when hidden is disabled", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
  })

  local original_hidden = vim.o.hidden
  vim.o.hidden = false
  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(source_bufnr)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  })
  vim.bo[source_bufnr].filetype = "markdown"
  vim.bo[source_bufnr].bufhidden = ""
  vim.bo[source_bufnr].modified = true

  local reader_bufnr = plugin.reader_preview()
  h.assert_true("reader opens for unsaved source", reader_bufnr ~= nil)
  h.assert_eq("source temporarily uses bufhidden hide", vim.bo[source_bufnr].bufhidden, "hide")
  plugin.close_reader()
  h.assert_eq("source bufhidden is restored", vim.bo[source_bufnr].bufhidden, "")
  h.assert_true("unsaved source remains modified", vim.bo[source_bufnr].modified)
  plugin.state.paused_buffers[source_bufnr] = nil
  vim.api.nvim_buf_delete(source_bufnr, { force = true })
  vim.o.hidden = original_hidden
end)
