local M = {}
local markdown = require("markdown-table-wrap.markdown")

local function trim(value)
  if type(value) == "table" then
    value = value.text or ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function iter_chars(text)
  return (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
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

local function has_unescaped_pipe(line)
  local code_ticks = nil
  local escaped = false
  local index = 1

  while index <= #line do
    local ch, _, end_col = next_char_at(line, index)
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
      return true
    end

    index = end_col + 1
    ::continue::
  end

  return false
end

local function split_pipe_row(line)
  local cells = {}
  local current = {}
  local code_ticks = nil
  local escaped = false
  local index = 1

  while index <= #line do
    local ch, _, end_col = next_char_at(line, index)
    if not ch then
      break
    end

    if escaped then
      table.insert(current, ch)
      escaped = false
    elseif ch == "\\" then
      escaped = true
      table.insert(current, ch)
    elseif ch == "`" then
      local count, run_end = backtick_run_at(line, index)
      table.insert(current, line:sub(index, run_end))
      if not code_ticks then
        code_ticks = count
      elseif count == code_ticks then
        code_ticks = nil
      end
      index = run_end + 1
      goto continue
    elseif ch == "|" and not code_ticks then
      table.insert(cells, trim(table.concat(current)))
      current = {}
    else
      table.insert(current, ch)
    end

    index = end_col + 1
    ::continue::
  end

  table.insert(cells, trim(table.concat(current)))

  if vim.startswith(line, "|") then
    table.remove(cells, 1)
  end

  if vim.endswith(line, "|") then
    table.remove(cells)
  end

  for index, cell in ipairs(cells) do
    cells[index] = markdown.parse_inline(cell:gsub("\\|", "|"))
  end

  return cells
end

local function is_separator_cell(cell)
  local value = trim(cell):gsub("%s+", "")
  value = value:gsub("^:", ""):gsub(":$", "")
  return #value >= 3 and value:match("^%-+$") ~= nil
end

local function parse_alignment(cell)
  local value = trim(cell):gsub("%s+", "")
  local starts = vim.startswith(value, ":")
  local ends = vim.endswith(value, ":")

  if starts and ends then
    return "center"
  elseif ends then
    return "right"
  elseif starts then
    return "left"
  end

  return "left"
end

local function is_separator_row(line)
  if not has_unescaped_pipe(line) then
    return false
  end

  local cells = split_pipe_row(line)
  if #cells == 0 then
    return false
  end

  for _, cell in ipairs(cells) do
    if not is_separator_cell(cell) then
      return false
    end
  end

  return true
end

local function is_tableish_line(line)
  return line and trim(line) ~= "" and has_unescaped_pipe(line)
end

local function normalize_row(row, count)
  local normalized = {}

  for index = 1, count do
    normalized[index] = row[index] or markdown.parse_inline("")
  end

  return normalized
end

function M.parse_at_cursor(bufnr, cursor_lnum)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local current = vim.api.nvim_buf_get_lines(bufnr, cursor_lnum - 1, cursor_lnum, false)[1] or ""

  if not is_tableish_line(current) then
    return nil, "MarkdownTableWrap: cursor is not inside a Markdown pipe table."
  end

  local start_lnum = cursor_lnum
  while start_lnum > 1 do
    local previous = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 2, start_lnum - 1, false)[1]
    if not is_tableish_line(previous) then
      break
    end
    start_lnum = start_lnum - 1
  end

  local end_lnum = cursor_lnum
  while end_lnum < total do
    local next_line = vim.api.nvim_buf_get_lines(bufnr, end_lnum, end_lnum + 1, false)[1]
    if not is_tableish_line(next_line) then
      break
    end
    end_lnum = end_lnum + 1
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  local cursor_index = cursor_lnum - start_lnum + 1
  local separator_index = nil

  for index, line in ipairs(lines) do
    if index > 1 and is_separator_row(line) and cursor_index >= index - 1 then
      separator_index = index
      break
    end
  end

  if not separator_index then
    return nil, "MarkdownTableWrap: no valid Markdown table separator row found."
  end

  start_lnum = start_lnum + separator_index - 2
  lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum - 1, end_lnum, false)
  separator_index = 2

  local header = split_pipe_row(lines[separator_index - 1])
  local separator = split_pipe_row(lines[separator_index])

  if #header == 0 then
    return nil, "MarkdownTableWrap: table header is empty."
  end

  if #separator ~= #header then
    return nil, "MarkdownTableWrap: table separator column count does not match the header."
  end

  local align = {}
  for index = 1, #header do
    align[index] = parse_alignment(separator[index] or "---")
  end

  local rows = {}
  for index = separator_index + 1, #lines do
    table.insert(rows, normalize_row(split_pipe_row(lines[index]), #header))
  end

  return {
    start_lnum = start_lnum,
    separator_lnum = start_lnum + separator_index - 1,
    end_lnum = end_lnum,
    header = normalize_row(header, #header),
    align = align,
    rows = rows,
  }
end

function M.parse_all(bufnr)
  local tables = {}
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lnum = 1

  while lnum <= total do
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

    if is_tableish_line(line) then
      local table_info = M.parse_at_cursor(bufnr, lnum)
      if table_info then
        table.insert(tables, table_info)
        lnum = table_info.end_lnum + 1
      else
        lnum = lnum + 1
      end
    else
      lnum = lnum + 1
    end
  end

  return tables
end

return M
