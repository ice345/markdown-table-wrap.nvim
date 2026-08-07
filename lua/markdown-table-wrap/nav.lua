local M = {}

local function iter_chars_with_pos(text)
  local index = 1
  return function()
    if index > #text then
      return nil
    end

    local start_col, end_col, ch = text:find("([%z\1-\127\194-\244][\128-\191]*)", index)
    if not start_col then
      return nil
    end

    index = end_col + 1
    return ch, start_col, end_col
  end
end

local function next_char_at(text, index)
  local start_col, end_col, ch = text:find("([%z\1-\127\194-\244][\128-\191]*)", index)
  if not start_col then
    return nil
  end
  return ch, start_col, end_col
end

local function backtick_run_at(text, index)
  local count = 0
  local cursor = index

  while cursor <= #text do
    local ch, _, end_col = next_char_at(text, cursor)
    if ch ~= "`" then
      break
    end
    count = count + 1
    cursor = end_col + 1
  end

  return count, cursor - 1
end

local function pipe_positions(line)
  local positions = {}
  local code_ticks = nil
  local escaped = false

  local index = 1
  while index <= #line do
    local ch, start_col, end_col = next_char_at(line, index)
    if not ch then
      break
    end

    if escaped then
      escaped = false
    elseif ch == "\\" then
      escaped = true
    elseif ch == "`" then
      local count, run_end = backtick_run_at(line, index)
      if not code_ticks then
        code_ticks = count
      elseif count == code_ticks then
        code_ticks = nil
      end
      index = run_end + 1
      goto continue
    elseif ch == "|" and not code_ticks then
      table.insert(positions, start_col)
    end

    index = end_col + 1
    ::continue::
  end

  return positions
end

local function trim_span(line, left, right)
  while left <= right and line:sub(left, left):match("%s") do
    left = left + 1
  end

  while right >= left and line:sub(right, right):match("%s") do
    right = right - 1
  end

  return left, right
end

local function cell_spans(line)
  local pipes = pipe_positions(line)
  if #pipes == 0 then
    return {}
  end

  local bounds = { 0 }
  for _, position in ipairs(pipes) do
    table.insert(bounds, position)
  end
  table.insert(bounds, #line + 1)

  local spans = {}
  for index = 1, #bounds - 1 do
    local left = bounds[index] + 1
    local right = bounds[index + 1] - 1
    local is_outer_left = index == 1 and vim.startswith(line, "|")
    local is_outer_right = index == #bounds - 1 and vim.endswith(line, "|")

    if not is_outer_left and not is_outer_right then
      local text_left, text_right = trim_span(line, left, right)
      if text_left > text_right then
        text_left = left
        text_right = right
      end

      table.insert(spans, {
        start_col = math.max(text_left - 1, 0),
        end_col = math.max(text_right, 0),
      })
    end
  end

  return spans
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

function M.move_horizontal(direction)
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

function M.move_vertical(direction)
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
