local M = {}
local markdown = require("markdown-table-wrap.markdown")

local function trim(value)
  if type(value) == "table" then
    value = value.text or ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
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

local function fence_parts(line)
  local indent, marker, tail = line:match("^( *)([`~]+)(.*)$")
  if not marker or #indent > 3 or #marker < 3 then
    return nil
  end

  local char = marker:sub(1, 1)
  if marker:match("^" .. char .. "+$") == nil then
    return nil
  end

  return char, #marker, tail
end

local function fence_opener(line)
  local char, length, tail = fence_parts(line)
  if not char or (char == "`" and tail:find("`", 1, true)) then
    return nil
  end

  return char, length
end

local function is_fence_closer(line, fence_char, fence_length)
  local char, length, tail = fence_parts(line)
  return char == fence_char and length >= fence_length and tail:match("^[ \t]*$") ~= nil
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

local function split_pipe_row(line, lnum, references)
  local segments = {}
  local code_ticks = nil
  local escaped = false
  local segment_start = 1
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
      table.insert(segments, { start_col = segment_start, end_col = index - 1 })
      segment_start = end_col + 1
    end

    index = end_col + 1
    ::continue::
  end

  table.insert(segments, { start_col = segment_start, end_col = #line })

  local stripped = trim(line)
  if vim.startswith(stripped, "|") then
    table.remove(segments, 1)
  end
  local last_segment = segments[#segments]
  if last_segment and line:sub(last_segment.start_col, last_segment.end_col):match("^%s*$") and #segments > 1 then
    table.remove(segments)
  end

  local cells = {}
  for cell_index, segment in ipairs(segments) do
    local start_col = segment.start_col
    local end_col = segment.end_col
    while start_col <= end_col and line:sub(start_col, start_col):match("%s") do
      start_col = start_col + 1
    end
    while end_col >= start_col and line:sub(end_col, end_col):match("%s") do
      end_col = end_col - 1
    end

    local raw = start_col <= end_col and line:sub(start_col, end_col) or ""
    local cell = markdown.parse_inline(raw, { references = references })
    cell.raw = raw
    cell.present = true
    cell.column_index = cell_index
    cell.source_span = {
      start_lnum = lnum,
      start_col = start_col - 1,
      end_lnum = lnum,
      end_col = math.max(start_col - 1, end_col),
    }
    for _, token in ipairs(cell.tokens or {}) do
      token.cell_source_start_col = token.source_start_col
      token.cell_source_end_col = token.source_end_col
      token.source_start_col = cell.source_span.start_col + token.source_start_col
      token.source_end_col = cell.source_span.start_col + token.source_end_col
    end
    for _, span in ipairs(cell.spans or {}) do
      span.cell_source_start_col = span.source_start_col
      span.cell_source_end_col = span.source_end_col
      span.source_start_col = cell.source_span.start_col + span.source_start_col
      span.source_end_col = cell.source_span.start_col + span.source_end_col
    end
    table.insert(cells, cell)
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

local function starts_atx_heading(content)
  local hashes = content:match("^(#+)")
  if not hashes or #hashes > 6 then
    return false
  end

  local next_char = content:sub(#hashes + 1, #hashes + 1)
  return next_char == "" or next_char == " " or next_char == "\t"
end

local function starts_list(content)
  if content:match("^[-+*][ \t]+") then
    return true
  end

  local digits, suffix = content:match("^(%d+)([.)])")
  if not digits or #digits > 9 then
    return false
  end

  local next_char = content:sub(#digits + #suffix + 1, #digits + #suffix + 1)
  return next_char == " " or next_char == "\t"
end

local function is_thematic_break(content)
  local compact = content:gsub("[ \t]", "")
  return compact:match("^%*%*%*+$") ~= nil or compact:match("^___+$") ~= nil or compact:match("^%-%-%-+$") ~= nil
end

local html_block_tags = {
  address = true,
  article = true,
  aside = true,
  base = true,
  basefont = true,
  blockquote = true,
  body = true,
  caption = true,
  center = true,
  col = true,
  colgroup = true,
  dd = true,
  details = true,
  dialog = true,
  dir = true,
  div = true,
  dl = true,
  dt = true,
  fieldset = true,
  figcaption = true,
  figure = true,
  footer = true,
  form = true,
  frame = true,
  frameset = true,
  h1 = true,
  h2 = true,
  h3 = true,
  h4 = true,
  h5 = true,
  h6 = true,
  head = true,
  header = true,
  hr = true,
  html = true,
  iframe = true,
  legend = true,
  li = true,
  link = true,
  main = true,
  menu = true,
  menuitem = true,
  nav = true,
  noframes = true,
  ol = true,
  optgroup = true,
  option = true,
  p = true,
  param = true,
  pre = true,
  script = true,
  search = true,
  section = true,
  style = true,
  summary = true,
  table = true,
  tbody = true,
  td = true,
  tfoot = true,
  th = true,
  thead = true,
  title = true,
  tr = true,
  track = true,
  ul = true,
}

local function starts_html_block(content)
  if
    content:match("^<!%-%-")
    or content:match("^<%?")
    or content:match("^<![A-Z]")
    or content:match("^<!%[CDATA%[")
  then
    return true
  end

  local tag, tail = content:match("^</?([A-Za-z][A-Za-z0-9-]*)(.*)$")
  if not tag or not html_block_tags[tag:lower()] then
    return false
  end

  return tail == "" or tail:match("^[ \t/>]") ~= nil
end

local function starts_block(line)
  local indent, content = line:match("^( *)(.*)$")
  if #indent >= 4 then
    return true
  end

  if content:sub(1, 1) == ">" then
    return true
  end

  if fence_opener(line) then
    return true
  end

  if starts_atx_heading(content) or starts_list(content) or is_thematic_break(content) then
    return true
  end

  if starts_html_block(content) then
    return true
  end

  return content:match("^%[[^%]]+%]:[ \t]*%S") ~= nil
end

local function normalize_row(row, count, lnum, line, kind)
  local normalized = {}
  local line_end = #(line or "")

  for index = 1, count do
    local cell = row[index]
    if not cell then
      cell = markdown.parse_inline("")
      cell.raw = ""
      cell.present = false
      cell.source_span = {
        start_lnum = lnum,
        start_col = line_end,
        end_lnum = lnum,
        end_col = line_end,
      }
    end
    cell.column_index = index
    normalized[index] = cell
  end

  normalized.kind = kind
  normalized.source_lnum = lnum
  normalized.source_span = { start_lnum = lnum, start_col = 0, end_lnum = lnum, end_col = line_end }
  normalized.raw_cell_count = #row
  normalized.overflow_cells = {}
  for index = count + 1, #row do
    table.insert(normalized.overflow_cells, row[index])
  end

  return normalized
end

local function parse_table_at(lines, start_lnum, references)
  local header_line = lines[start_lnum]
  local separator_line = lines[start_lnum + 1]

  if
    not separator_line
    or not is_tableish_line(header_line)
    or starts_block(header_line)
    or starts_block(separator_line)
    or not is_separator_row(separator_line)
  then
    return nil
  end

  local header = split_pipe_row(header_line, start_lnum, references)
  local separator = split_pipe_row(separator_line, start_lnum + 1, references)

  if #header == 0 then
    return nil
  end

  if #separator ~= #header then
    return nil
  end

  local align = {}
  for index = 1, #header do
    align[index] = parse_alignment(separator[index] or "---")
  end

  local rows = {}
  local end_lnum = start_lnum + 1
  local lnum = start_lnum + 2

  while lnum <= #lines do
    local line = lines[lnum]
    if trim(line) == "" or starts_block(line) then
      break
    end

    table.insert(rows, normalize_row(split_pipe_row(line, lnum, references), #header, lnum, line, "body"))
    end_lnum = lnum
    lnum = lnum + 1
  end

  local table_id = string.format("%d:%d", start_lnum, end_lnum)
  local normalized_header = normalize_row(header, #header, start_lnum, header_line, "header")
  for row_index, row in ipairs(rows) do
    row.row_index = row_index
    row.table_id = table_id
    for _, cell in ipairs(row) do
      cell.row_index = row_index
      cell.table_id = table_id
    end
    for _, cell in ipairs(row.overflow_cells or {}) do
      cell.row_index = row_index
      cell.table_id = table_id
    end
  end
  normalized_header.row_index = 0
  normalized_header.table_id = table_id
  for _, cell in ipairs(normalized_header) do
    cell.row_index = 0
    cell.table_id = table_id
  end
  for _, cell in ipairs(separator) do
    cell.row_index = -1
    cell.table_id = table_id
  end

  return {
    id = table_id,
    start_lnum = start_lnum,
    separator_lnum = start_lnum + 1,
    end_lnum = end_lnum,
    source_span = {
      start_lnum = start_lnum,
      start_col = 0,
      end_lnum = end_lnum,
      end_col = #(lines[end_lnum] or ""),
    },
    header = normalized_header,
    delimiter = {
      source_lnum = start_lnum + 1,
      source_span = {
        start_lnum = start_lnum + 1,
        start_col = 0,
        end_lnum = start_lnum + 1,
        end_col = #separator_line,
      },
      cells = separator,
    },
    align = align,
    rows = rows,
  }
end

local function collect_references(lines)
  local references = {}
  for lnum, line in ipairs(lines) do
    local label, target = line:match("^%s?%s?%s?%[([^%]]+)%]:%s*(%S+)")
    if label and target then
      if target:sub(1, 1) == "<" and target:sub(-1) == ">" then
        target = target:sub(2, -2)
      end
      references[vim.trim(label):gsub("%s+", " "):lower()] = {
        target = target,
        source_span = { start_lnum = lnum, start_col = 0, end_lnum = lnum, end_col = #line },
      }
    end
  end
  return references
end

local function parse_lines(lines, stop_lnum, opts)
  local tables = {}
  local fenced_lines = {}
  local fence_char = nil
  local fence_length = nil
  local lnum = 1
  local references = (opts or {}).references or collect_references(lines)

  if opts and opts.ranges then
    for _, range in ipairs(opts.ranges) do
      if not stop_lnum or range.start_lnum <= stop_lnum then
        local table_info = parse_table_at(lines, range.start_lnum, references)
        if table_info then
          table_info.discovery_backend = range.backend or "lua"
          table.insert(tables, table_info)
        end
      end
    end
    return tables, fenced_lines
  end

  while lnum <= #lines and (not stop_lnum or lnum <= stop_lnum) do
    local line = lines[lnum]

    if fence_char then
      fenced_lines[lnum] = true
      if is_fence_closer(line, fence_char, fence_length) then
        fence_char = nil
        fence_length = nil
      end
      lnum = lnum + 1
    else
      local opener_char, opener_length = fence_opener(line)
      if opener_char then
        fenced_lines[lnum] = true
        fence_char = opener_char
        fence_length = opener_length
        lnum = lnum + 1
      else
        local table_info = parse_table_at(lines, lnum, references)
        if table_info then
          table.insert(tables, table_info)
          lnum = table_info.end_lnum + 1
        else
          lnum = lnum + 1
        end
      end
    end
  end

  return tables, fenced_lines
end

function M.parse_at_cursor(bufnr, cursor_lnum)
  local tables = M.parse_all(bufnr)

  for _, table_info in ipairs(tables) do
    if cursor_lnum >= table_info.start_lnum and cursor_lnum <= table_info.end_lnum then
      return table_info
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local _, fenced_lines = parse_lines(lines, cursor_lnum)

  if fenced_lines[cursor_lnum] then
    return nil, "MarkdownTableWrap: cursor is inside a fenced code block."
  end

  local current = lines[cursor_lnum] or ""
  if not is_tableish_line(current) then
    return nil, "MarkdownTableWrap: cursor is not inside a Markdown pipe table."
  end

  return nil, "MarkdownTableWrap: no valid Markdown table separator row found."
end

function M.parse_all(bufnr, opts)
  opts = type(opts) == "table" and opts or {}
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local backend = opts.backend or (opts.discovery or {}).backend or "default"
  local cache_key = table.concat({ tostring(backend), tostring(opts.cache ~= false) }, "\31")
  local cache = require("markdown-table-wrap.cache")
  local cached = opts.cache == false and nil or cache.get(bufnr, "parse", cache_key, changedtick)
  if cached then
    return cached
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local discovery_key = backend
  local ranges = opts.cache == false and nil or cache.get(bufnr, "discovery", discovery_key, changedtick)
  if not ranges then
    ranges = require("markdown-table-wrap.discovery").discover(
      bufnr,
      lines,
      { backend = backend ~= "default" and backend or nil }
    )
    if opts.cache ~= false then
      cache.set(bufnr, "discovery", discovery_key, changedtick, ranges)
    end
  end
  local tables = parse_lines(lines, nil, { ranges = ranges })
  for _, table_info in ipairs(tables) do
    table_info.source_bufnr = bufnr
    table_info.changedtick = changedtick
    table_info.id = string.format("%d:%s", bufnr, table_info.id)
    table_info.source_signature = table.concat({ changedtick, table_info.start_lnum, table_info.end_lnum }, ":")
    table_info.header.table_id = table_info.id
    for _, cell in ipairs(table_info.header) do
      cell.table_id = table_info.id
    end
    for _, cell in ipairs(table_info.delimiter.cells or {}) do
      cell.table_id = table_info.id
    end
    for _, row in ipairs(table_info.rows) do
      row.table_id = table_info.id
      for _, cell in ipairs(row) do
        cell.table_id = table_info.id
      end
      for _, cell in ipairs(row.overflow_cells or {}) do
        cell.table_id = table_info.id
      end
    end
  end
  if opts.cache ~= false then
    cache.set(bufnr, "parse", cache_key, changedtick, tables)
  end
  return tables
end

function M.parse_lines(lines, opts)
  if type(lines) ~= "table" then
    error("lines: expected table, got " .. type(lines), 2)
  end
  local tables = parse_lines(lines, nil, opts)
  return tables
end

function M.references(lines)
  if type(lines) ~= "table" then
    error("lines: expected table, got " .. type(lines), 2)
  end
  return collect_references(lines)
end

return M
