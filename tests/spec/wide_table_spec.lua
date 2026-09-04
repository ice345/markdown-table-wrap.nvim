local h = require("tests.helpers")

local function parse_table(lines)
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  local model = parser.parse_at_cursor(buf, 3)
  return buf, model, render
end

local function base_config()
  return {
    max_width_ratio = 1,
    min_col_width = 3,
    max_col_width = 20,
    fit_to_window = true,
    use_unicode_border = true,
    table_border = "single",
    row_separator = false,
    link = {},
  }
end

h.test("wide table column rules honor fixed and bounded widths", function()
  local buf, model, render = parse_table({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| short | a much longer value | tail |",
  })
  vim.api.nvim_win_set_width(0, 100)
  local config = base_config()
  config.wide_table = {
    mode = "wrap",
    allocate_extra = true,
    columns = {
      [1] = { width = 5 },
      [2] = { min = 8, max = 10, weight = 2 },
      [3] = { min = 4, max = 4 },
    },
  }
  local output = render.render_table(model, config)
  h.assert_eq("fixed column width is exact", output.column_widths[1], 5)
  h.assert_true("bounded column does not exceed maximum", output.column_widths[2] <= 10)
  h.assert_eq("bounded column minimum is retained", output.column_widths[3], 4)
  h.assert_eq("all columns remain visible in wrap mode", #output.visible_columns, 3)
  h.assert_false("wrap mode has no hidden marker", output.hidden_columns.left)
  h.assert_eq("temporary buffer can be removed", vim.api.nvim_buf_delete(buf, { force = true }), nil)
end)

h.test("viewport mode renders a contiguous column slice with markers", function()
  local buf, model, render = parse_table({
    "| A | B | C | D |",
    "| --- | --- | --- | --- |",
    "| one | two | three | four |",
  })
  local config = base_config()
  config.wide_table = {
    mode = "viewport",
    viewport = { start_column = 2, column_count = 2, marker = "…" },
    columns = {},
  }
  local output = render.render_table(model, config)
  h.assert_deep_eq("viewport selects requested columns", output.visible_columns, { 2, 3 })
  h.assert_true("left hidden marker is reported", output.hidden_columns.left)
  h.assert_true("right hidden marker is reported", output.hidden_columns.right)
  h.assert_true("rendered top line has a left marker", vim.startswith(output.lines[1], "…"))
  h.assert_true("rendered body line has a right marker", vim.endswith(output.lines[4], "…"))
  for _, object in ipairs(output.line_objects) do
    for _, cell in ipairs(object.cells or {}) do
      h.assert_true("visible segment keeps source column", cell.column_index == 2 or cell.column_index == 3)
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end)

h.test("viewport helper keeps the active column visible", function()
  local render = require("markdown-table-wrap.render")
  local config = {
    wide_table = {
      mode = "viewport",
      viewport = { start_column = 2, column_count = 2, marker = "…" },
    },
  }
  config = render.ensure_viewport(config, 6, 1)
  h.assert_eq("active column shifts viewport left", config.wide_table.viewport.start_column, 1)
  config = render.ensure_viewport(config, 6, 5)
  h.assert_eq("active column shifts viewport right", config.wide_table.viewport.start_column, 4)
end)

h.test("impossible fixed constraints are deterministic and inspectable", function()
  local buf, model, render = parse_table({
    "| A | B |",
    "| --- | --- |",
    "| first | second |",
  })
  vim.api.nvim_win_set_width(0, 24)
  local config = base_config()
  config.max_width_ratio = 0.5
  config.wide_table = {
    mode = "wrap",
    columns = {
      [1] = { width = 20 },
      [2] = { width = 20 },
    },
  }
  local first = render.render_table(model, config)
  local second = render.render_table(model, config)
  h.assert_true("overflow is reported", first.layout.overflow)
  h.assert_deep_eq("overflow layout is deterministic", first.column_widths, second.column_widths)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

h.test("viewport movement reports wrap mode instead of silently doing nothing", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, wide_table = { mode = "wrap" } })
  local original_notify = vim.notify
  local message
  vim.notify = function(value)
    message = value
  end
  h.assert_false("wrap mode refuses viewport movement", plugin.shift_wide_table_viewport(1))
  vim.notify = original_notify
  h.assert_true("wrap-mode refusal explains viewport mode", message:find("wide_table.mode", 1, true) ~= nil)
end)

h.test("viewport commands refresh an open Float against its Source state", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    wide_table = { mode = "viewport", viewport = { start_column = 1, column_count = 1 } },
  })
  h.with_buffer({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| one | two | three |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    plugin.float_preview()
    h.assert_true("Float viewport advances", plugin.shift_wide_table_viewport(1))
    h.assert_eq("Float keeps its Source identity", plugin.state.float_source_bufnr, source_bufnr)
    h.assert_deep_eq("Float rerenders the requested slice", plugin.state.float_rendered.visible_columns, { 2 })
    plugin.close_preview()
  end)
end)
