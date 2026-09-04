local parser = require("markdown-table-wrap.parser")
local width = require("markdown-table-wrap.width")

local M = {}
local popup_state = nil

local function popup_dimensions(lines)
  local max_width = math.max(1, vim.o.columns - 4)
  local min_width = math.min(30, max_width)
  local longest = 0
  for _, line in ipairs(lines or {}) do
    longest = math.max(longest, width.strwidth(line))
  end
  local popup_width = math.min(max_width, math.max(min_width, longest + 4))
  local content_width = math.max(1, popup_width - 2)
  local display_lines = 0
  for _, line in ipairs(lines or {}) do
    display_lines = display_lines + math.max(1, math.ceil(width.strwidth(line) / content_width))
  end
  local max_height = math.max(3, math.min(12, vim.o.lines - vim.o.cmdheight - 4))
  return popup_width, math.min(max_height, math.max(3, display_lines))
end

local function resize_cell_popup()
  if not popup_state or not popup_state.buf or not popup_state.win then
    return
  end
  if not vim.api.nvim_buf_is_valid(popup_state.buf) or not vim.api.nvim_win_is_valid(popup_state.win) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(popup_state.buf, 0, -1, false)
  local popup_width, popup_height = popup_dimensions(lines)
  pcall(vim.api.nvim_win_set_config, popup_state.win, {
    relative = "editor",
    width = popup_width,
    height = popup_height,
    row = math.max(0, math.floor((vim.o.lines - popup_height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - popup_width) / 2)),
  })
end

local function notify(message, level, opts)
  if not (opts or {}).silent then
    vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
  end
end

local function source_context(opts)
  opts = opts or {}
  local context, err = require("markdown-table-wrap.context").resolve(opts)
  if not context then
    notify(err or "could not resolve the active Markdown Source", vim.log.levels.ERROR, opts)
    return nil
  end

  if context.mode == "reader" then
    if not require("markdown-table-wrap").close_reader() then
      return nil
    end
    context = require("markdown-table-wrap.context").resolve()
  elseif context.mode == "float" then
    local plugin = require("markdown-table-wrap")
    local source_winid = plugin.state.float_source_winid
    plugin.close_preview({ restore_origin = false })
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    end
    context = require("markdown-table-wrap.context").resolve()
  elseif context.mode == "inline" then
    require("markdown-table-wrap.inline").clear(context.source_bufnr)
  end
  return context
end

local function current_table(context, opts)
  local table_info = context and context.table
  if table_info and table_info.id then
    for _, candidate in ipairs(parser.parse_all(context.source_bufnr)) do
      if candidate.id == table_info.id then
        return candidate
      end
    end
  end
  local parsed = parser.parse_at_cursor(context.source_bufnr, context.cursor.source_lnum)
  return parsed
end

local function safe_table(table_info, opts)
  if not table_info then
    notify("place the cursor inside a Markdown pipe table", vim.log.levels.INFO, opts)
    return false
  end
  for _, row in ipairs(table_info.rows or {}) do
    if #(row.overflow_cells or {}) > 0 or (row.raw_cell_count or 0) > #table_info.header then
      notify("table contains excess cells; structural editing was refused", vim.log.levels.ERROR, opts)
      return false
    end
  end
  return true
end

local function raw_cell(cell)
  return cell and cell.present ~= false and (cell.raw or cell.text or "") or ""
end

local function single_line(value)
  local text = tostring(value or "")
  return (text:gsub("[\r\n]+", " "))
end

local function rows_from(table_info)
  local rows = { {} }
  for index, cell in ipairs(table_info.header) do
    rows[1][index] = raw_cell(cell)
  end
  for _, row in ipairs(table_info.rows or {}) do
    local values = {}
    for index = 1, #table_info.header do
      values[index] = raw_cell(row[index])
    end
    table.insert(rows, values)
  end
  return rows
end

local function source_width(value)
  return math.max(1, width.strwidth(value or ""))
end

local function format_delimiter(alignment, target_width)
  target_width = math.max(alignment == "center" and 5 or 4, target_width or 3)
  if alignment == "center" then
    return ":" .. string.rep("-", math.max(1, target_width - 2)) .. ":"
  elseif alignment == "right" then
    return string.rep("-", math.max(1, target_width - 1)) .. ":"
  end
  return ":" .. string.rep("-", math.max(1, target_width - 1))
end

local function format_row(values, widths, alignments)
  local parts = { "|" }
  for index, value in ipairs(values) do
    local padded = width.pad(value or "", widths[index] or 1, alignments[index] or "left")
    table.insert(parts, " " .. padded .. " ")
    table.insert(parts, "|")
  end
  return table.concat(parts)
end

local function canonical_lines(table_info, rows, alignments)
  local columns = #(rows[1] or table_info.header)
  local widths = {}
  for index = 1, columns do
    local target = alignments[index] == "center" and 5 or 4
    for _, row in ipairs(rows) do
      target = math.max(target, source_width(row[index] or ""))
    end
    widths[index] = target
  end

  local lines = { format_row(rows[1], widths, alignments) }
  local delimiters = {}
  local delimiter_alignments = {}
  for index = 1, columns do
    delimiters[index] = format_delimiter(alignments[index], widths[index])
    delimiter_alignments[index] = "left"
  end
  table.insert(lines, format_row(delimiters, widths, delimiter_alignments))
  for index = 2, #rows do
    table.insert(lines, format_row(rows[index], widths, alignments))
  end
  local prefix = (table_info.container or {}).render_prefix or ""
  if prefix ~= "" then
    for index, line in ipairs(lines) do
      lines[index] = prefix .. line
    end
  end
  return lines
end

local function replace_table(context, table_info, rows, alignments, opts)
  if not safe_table(table_info, opts) then
    return false
  end
  local source_bufnr = context.source_bufnr
  if
    not vim.api.nvim_buf_is_valid(source_bufnr)
    or not vim.bo[source_bufnr].modifiable
    or vim.bo[source_bufnr].readonly
  then
    notify("the backing Source buffer is read-only", vim.log.levels.ERROR, opts)
    return false
  end
  local lines = canonical_lines(table_info, rows, alignments)
  local ok, err =
    pcall(vim.api.nvim_buf_set_lines, source_bufnr, table_info.start_lnum - 1, table_info.end_lnum, false, lines)
  if not ok then
    notify("could not rewrite the Markdown table: " .. tostring(err), vim.log.levels.ERROR, opts)
    return false
  end
  local target_lnum = math.max(table_info.start_lnum, math.min(table_info.end_lnum, context.cursor.source_lnum))
  if vim.api.nvim_get_current_buf() == source_bufnr then
    vim.api.nvim_win_set_cursor(0, { math.min(target_lnum, vim.api.nvim_buf_line_count(source_bufnr)), 0 })
  end
  notify("updated Markdown table in one undo step", vim.log.levels.INFO, opts)
  return true
end

local function table_and_rows(opts)
  local context = source_context(opts)
  if not context then
    return nil
  end
  local table_info = current_table(context, opts)
  if not safe_table(table_info, opts) then
    return nil
  end
  return context, table_info, rows_from(table_info)
end

local function current_row(table_info, context, opts)
  local explicit = tonumber(opts and opts.index)
  local index = explicit or (context.cell and context.cell.row_index)
  if not explicit and (index == nil or index <= 0) then
    notify("place the cursor in a table body row", vim.log.levels.INFO, opts)
    return nil
  end
  index = index or 1
  return math.max(1, math.min(#table_info.rows, math.floor(index)))
end

local function current_column(table_info, context, opts)
  local index = tonumber(opts and opts.index) or (context.cell and context.cell.index) or 1
  return math.max(1, math.min(#table_info.header, math.floor(index)))
end

function M.format(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context then
    return false
  end
  return replace_table(context, table_info, rows, vim.deepcopy(table_info.align), opts)
end

function M.add_row(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context then
    return false
  end
  local values = type(opts and opts.values) == "table" and opts.values or {}
  local row = {}
  for index = 1, #table_info.header do
    row[index] = single_line(values[index])
  end
  local position = tonumber(opts and opts.index)
    or ((context.cell and context.cell.row_index or 0) > 0 and context.cell.row_index + 1 or #table_info.rows + 1)
  position = math.max(1, math.min(#table_info.rows + 1, math.floor(position)))
  table.insert(rows, position + 1, row)
  local ok = replace_table(context, table_info, rows, vim.deepcopy(table_info.align), opts)
  return ok
end

function M.delete_row(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context or #table_info.rows == 0 then
    return false
  end
  local position = current_row(table_info, context, opts)
  if not position then
    return false
  end
  table.remove(rows, position + 1)
  return replace_table(context, table_info, rows, vim.deepcopy(table_info.align), opts)
end

local function move_row(opts, direction)
  local context, table_info, rows = table_and_rows(opts)
  if not context or #table_info.rows < 2 then
    return false
  end
  local position = current_row(table_info, context, opts)
  if not position then
    return false
  end
  local target = math.max(1, math.min(#table_info.rows, position + direction))
  if target == position then
    return true
  end
  rows[position + 1], rows[target + 1] = rows[target + 1], rows[position + 1]
  return replace_table(context, table_info, rows, vim.deepcopy(table_info.align), opts)
end

function M.move_row_up(opts)
  return move_row(opts, -1)
end

function M.move_row_down(opts)
  return move_row(opts, 1)
end

function M.add_column(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context then
    return false
  end
  local position = tonumber(opts and opts.index) or ((context.cell and context.cell.index or #table_info.header) + 1)
  position = math.max(1, math.min(#table_info.header + 1, math.floor(position)))
  for _, row in ipairs(rows) do
    table.insert(row, position, "")
  end
  local alignments = vim.deepcopy(table_info.align)
  table.insert(alignments, position, "left")
  return replace_table(context, table_info, rows, alignments, opts)
end

function M.delete_column(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context or #table_info.header <= 1 then
    notify("a table must keep at least one column", vim.log.levels.ERROR, opts)
    return false
  end
  local position = current_column(table_info, context, opts)
  for _, row in ipairs(rows) do
    table.remove(row, position)
  end
  local alignments = vim.deepcopy(table_info.align)
  table.remove(alignments, position)
  return replace_table(context, table_info, rows, alignments, opts)
end

local function move_column(opts, direction)
  local context, table_info, rows = table_and_rows(opts)
  if not context or #table_info.header < 2 then
    return false
  end
  local position = current_column(table_info, context, opts)
  local target = math.max(1, math.min(#table_info.header, position + direction))
  if target == position then
    return true
  end
  for _, row in ipairs(rows) do
    row[position], row[target] = row[target], row[position]
  end
  local alignments = vim.deepcopy(table_info.align)
  alignments[position], alignments[target] = alignments[target], alignments[position]
  return replace_table(context, table_info, rows, alignments, opts)
end

function M.move_column_left(opts)
  return move_column(opts, -1)
end

function M.move_column_right(opts)
  return move_column(opts, 1)
end

function M.toggle_alignment(opts)
  local context, table_info, rows = table_and_rows(opts)
  if not context then
    return false
  end
  local position = current_column(table_info, context, opts)
  local alignments = vim.deepcopy(table_info.align)
  alignments[position] = ({ left = "center", center = "right", right = "left" })[alignments[position] or "left"]
  return replace_table(context, table_info, rows, alignments, opts)
end

function M.open_cell_popup(opts)
  opts = opts or {}
  if popup_state and popup_state.win and vim.api.nvim_win_is_valid(popup_state.win) then
    return popup_state.buf, popup_state.win
  end
  local context = source_context(opts)
  if not context or not context.cell then
    notify("place the cursor inside a table cell", vim.log.levels.INFO, opts)
    return false
  end
  local table_info = current_table(context, opts)
  if not safe_table(table_info, opts) then
    return false
  end
  local row = context.cell.row_index == 0 and table_info.header or table_info.rows[context.cell.row_index]
  local cell = row and row[context.cell.index]
  if
    not cell
    or cell.present == false
    or not cell.source_span
    or cell.source_span.start_lnum ~= cell.source_span.end_lnum
  then
    notify("this cell has no safe one-line Source range", vim.log.levels.ERROR, opts)
    return false
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { raw_cell(cell) })
  vim.b[buf].markdown_table_wrap_auxiliary = true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown-table-wrap-cell"
  vim.bo[buf].syntax = "markdown"
  local width_value, height_value = popup_dimensions({ raw_cell(cell) })
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width_value,
    height = height_value,
    row = math.max(0, math.floor((vim.o.lines - height_value) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width_value) / 2)),
    style = "minimal",
    border = context.config.border or "rounded",
    title = " MarkdownTableWrap Cell (Ctrl-S save, Esc cancel) ",
    title_pos = "center",
  })
  popup_state = {
    buf = buf,
    win = win,
    context = context,
    cell = cell,
    source_changedtick = vim.api.nvim_buf_get_changedtick(context.source_bufnr),
  }
  vim.bo[buf].modifiable = true
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = resize_cell_popup,
  })
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    M.commit_cell_popup()
  end, { buffer = buf, silent = true, desc = "Save Markdown table cell" })
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, function()
      M.close_cell_popup()
    end, { buffer = buf, silent = true, nowait = true, desc = "Cancel Markdown table cell" })
  end
  return buf, win
end

function M.commit_cell_popup(opts)
  opts = opts or {}
  if not popup_state or not popup_state.buf or not vim.api.nvim_buf_is_valid(popup_state.buf) then
    return false
  end
  local values = vim.api.nvim_buf_get_lines(popup_state.buf, 0, -1, false)
  local value = table.concat(values, " "):gsub("\r", "")
  local context = popup_state.context
  local source_bufnr = context.source_bufnr
  local span = popup_state.cell.source_span
  if
    not vim.api.nvim_buf_is_valid(source_bufnr)
    or not vim.bo[source_bufnr].modifiable
    or vim.bo[source_bufnr].readonly
  then
    notify("the backing Source buffer is read-only", vim.log.levels.ERROR, opts)
    return false
  end
  if
    popup_state.source_changedtick
    and vim.api.nvim_buf_get_changedtick(source_bufnr) ~= popup_state.source_changedtick
  then
    notify("the Source changed while the cell popup was open; reopen it", vim.log.levels.ERROR, opts)
    return false
  end
  vim.api.nvim_buf_set_text(
    source_bufnr,
    span.start_lnum - 1,
    span.start_col,
    span.end_lnum - 1,
    span.end_col,
    { value }
  )
  local win = popup_state.win
  popup_state = nil
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  notify("saved Markdown table cell in one undo step", vim.log.levels.INFO, opts)
  return true
end

function M.close_cell_popup()
  if not popup_state then
    return false
  end
  local win = popup_state.win
  local buf = popup_state.buf
  popup_state = nil
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  return true
end

function M.popup_state()
  return popup_state and vim.deepcopy(popup_state) or nil
end

return M
