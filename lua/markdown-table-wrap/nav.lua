local M = {}
local container = require("markdown-table-wrap.container")
local pipes = require("markdown-table-wrap.pipes")

local function cell_spans(line)
  local parsed = container.line(line)
  return pipes.cell_spans(parsed.content, parsed.content_start_col)
end

local function current_cell_index(spans, col)
  if #spans == 0 then
    return nil
  end

  for index, span in ipairs(spans) do
    if col >= span.start_col and col <= span.end_col then
      return index
    end
  end

  for index, span in ipairs(spans) do
    if col < span.start_col then
      return index
    end
  end

  return #spans
end

local function move_to_cell(row, cell_index)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ""
  local spans = cell_spans(line)
  local span = spans[cell_index]
  if not span then
    return false
  end

  vim.api.nvim_win_set_cursor(0, { row + 1, span.start_col })
  return true
end

local function move_source_horizontal(direction)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ""
  local spans = cell_spans(line)
  local current = current_cell_index(spans, col)

  if not current then
    return false
  end

  local target = math.max(1, math.min(#spans, current + direction))
  return move_to_cell(row, target)
end

local function move_source_vertical(direction)
  local parser = require("markdown-table-wrap.parser")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local bufnr = vim.api.nvim_get_current_buf()
  local table_info = parser.parse_at_cursor(bufnr, cursor[1])
  if not table_info then
    return false
  end

  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local spans = cell_spans(line)
  local current = current_cell_index(spans, col)
  if not current then
    return false
  end

  local target_row = math.max(table_info.start_lnum - 1, math.min(table_info.end_lnum - 1, row + direction))
  if table_info.separator_lnum and target_row == table_info.separator_lnum - 1 then
    target_row = math.max(table_info.start_lnum - 1, math.min(table_info.end_lnum - 1, target_row + direction))
  end

  return move_to_cell(target_row, current)
end

local function logical_table(context)
  if not context or not context.table or not context.cell or context.cell.row_index == nil then
    return nil
  end
  return require("markdown-table-wrap.parser").parse_at_cursor(context.source_bufnr, context.cursor.source_lnum)
end

local function source_lnum_for(table_info, row_index)
  if row_index == 0 then
    return table_info.start_lnum
  end
  local row = table_info.rows[row_index]
  return row and row.source_lnum or nil
end

local function focus_float_cell(context, table_id, row_index, column_index)
  local rendered = require("markdown-table-wrap").state.float_rendered
  local winid = context.winid
  if not rendered or not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  for row, object in ipairs(rendered.line_objects or {}) do
    for _, cell in ipairs(type(object) == "table" and object.cells or {}) do
      if cell.table_id == table_id and cell.row_index == row_index and cell.column_index == column_index then
        vim.api.nvim_win_set_cursor(winid, { row, cell.start_col })
        return true
      end
    end
  end
  return false
end

local function focus_logical_cell(context, table_info, row_index, column_index)
  local source_lnum = source_lnum_for(table_info, row_index)
  if not source_lnum then
    return false
  end
  if context.mode == "reader" then
    local wide = context.config.wide_table or {}
    if wide.mode == "viewport" then
      local adjusted =
        require("markdown-table-wrap.render").ensure_viewport(context.config, #table_info.header, column_index)
      local current = (wide.viewport or {}).start_column or 1
      local target = (((adjusted or {}).wide_table or {}).viewport or {}).start_column or current
      if target ~= current then
        require("markdown-table-wrap").set_wide_table_viewport(target, context.source_bufnr)
      end
    end
    return require("markdown-table-wrap.reader").focus_source_cell(
      context.view_bufnr,
      source_lnum,
      column_index,
      context.cell.table_id,
      row_index
    )
  end
  local wide = context.config.wide_table or {}
  if wide.mode == "viewport" then
    local adjusted =
      require("markdown-table-wrap.render").ensure_viewport(context.config, #table_info.header, column_index)
    local current = (wide.viewport or {}).start_column or 1
    local target = (((adjusted or {}).wide_table or {}).viewport or {}).start_column or current
    if target ~= current then
      require("markdown-table-wrap").set_wide_table_viewport(target, context.source_bufnr)
    end
  end
  return focus_float_cell(context, context.cell.table_id, row_index, column_index)
end

function M.move_horizontal(direction)
  local context = require("markdown-table-wrap.context").resolve()
  if not context or (context.mode ~= "reader" and context.mode ~= "float") then
    return move_source_horizontal(direction)
  end
  local table_info = logical_table(context)
  if not table_info then
    return false
  end
  local current = context.cell.index
  local target = math.max(1, math.min(#table_info.header, current + direction))
  return focus_logical_cell(context, table_info, context.cell.row_index, target)
end

function M.move_vertical(direction)
  local context = require("markdown-table-wrap.context").resolve()
  if not context or (context.mode ~= "reader" and context.mode ~= "float") then
    return move_source_vertical(direction)
  end
  local table_info = logical_table(context)
  if not table_info then
    return false
  end
  local target = math.max(0, math.min(#table_info.rows, context.cell.row_index + direction))
  return focus_logical_cell(context, table_info, target, context.cell.index)
end

function M.spans(line)
  return cell_spans(line)
end

function M.current_cell_text()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ""
  local spans = cell_spans(line)
  local current = current_cell_index(spans, col)
  local span = current and spans[current] or nil

  if not span then
    return nil
  end

  return vim.trim(line:sub(span.start_col + 1, span.end_col))
end

function M.open_link()
  local context = require("markdown-table-wrap.context").resolve()
  return context and require("markdown-table-wrap.links").open_at_context(context) or false
end

return M
