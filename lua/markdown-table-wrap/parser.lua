local M = {}
local markdown = require("markdown-table-wrap.markdown")
local container = require("markdown-table-wrap.container")
local fence = require("markdown-table-wrap.fence")
local pipes = require("markdown-table-wrap.pipes")

local function trim(value)
  if type(value) == "table" then
    value = value.text or ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_pipe_row(line, lnum, references, source_offset)
  source_offset = tonumber(source_offset) or 0
  local cells = {}
  for cell_index, segment in ipairs(pipes.segments(line)) do
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
      start_col = source_offset + start_col - 1,
      end_lnum = lnum,
      end_col = source_offset + math.max(start_col - 1, end_col),
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
  return #value >= 1 and value:match("^%-+$") ~= nil
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
  if not pipes.has(line) then
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
  return line and trim(line) ~= "" and pipes.has(line)
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

  if fence.opener(line) then
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
  local header_container = container.line(header_line)
  local separator_container = container.line(separator_line)

  if
    not separator_line
    or not container.same(header_container, separator_container)
    or not is_tableish_line(header_container.content)
    or starts_block(header_container.content)
    or starts_block(separator_container.content)
    or not is_separator_row(separator_container.content)
  then
    return nil
  end

  local header = split_pipe_row(header_container.content, start_lnum, references, header_container.content_start_col)
  local separator =
    split_pipe_row(separator_container.content, start_lnum + 1, references, separator_container.content_start_col)

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
    local row_container = container.line(line)
    if
      not container.same(header_container, row_container)
      or trim(row_container.content) == ""
      or starts_block(row_container.content)
    then
      break
    end

    table.insert(
      rows,
      normalize_row(
        split_pipe_row(row_container.content, lnum, references, row_container.content_start_col),
        #header,
        lnum,
        line,
        "body"
      )
    )
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
    container = header_container.kind == "blockquote" and {
      kind = header_container.kind,
      depth = header_container.depth,
      render_prefix = header_container.render_prefix,
    } or nil,
  }
end

local function collect_references(lines)
  local references = {}
  for lnum, line in ipairs(lines) do
    local content = container.line(line).content
    local label, target = content:match("^%s?%s?%s?%[([^%]]+)%]:%s*(%S+)")
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
  local lnum = 1
  local references = (opts or {}).references or collect_references(lines)

  if opts and opts.ranges then
    for _, range in ipairs(opts.ranges) do
      local lnum = range.start_lnum
      local finish = math.min(range.end_lnum or range.start_lnum, stop_lnum or #lines)
      while lnum <= finish do
        local table_info = parse_table_at(lines, lnum, references)
        if table_info then
          table_info.discovery_backend = range.backend or "lua"
          table.insert(tables, table_info)
          lnum = table_info.end_lnum + 1
        else
          lnum = lnum + 1
        end
      end
    end
    return tables, {}
  end

  local fenced_lines = fence.mask(lines)

  while lnum <= #lines and (not stop_lnum or lnum <= stop_lnum) do
    if fenced_lines[lnum] then
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

  local current = container.line(lines[cursor_lnum] or "").content
  if not is_tableish_line(current) then
    return nil, "MarkdownTableWrap: cursor is not inside a Markdown pipe table."
  end

  return nil, "MarkdownTableWrap: no valid Markdown table separator row found."
end

local function parse_all(bufnr, opts, readonly)
  opts = type(opts) == "table" and opts or {}
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local backend = opts.backend or (opts.discovery or {}).backend or "default"
  local cache_key = table.concat({ tostring(backend), tostring(opts.cache ~= false) }, "\31")
  local cache = require("markdown-table-wrap.cache")
  local cached
  if opts.cache ~= false then
    if readonly then
      cached = cache.get_ref(bufnr, "parse", cache_key, changedtick)
    else
      cached = cache.get(bufnr, "parse", cache_key, changedtick)
    end
  end
  if cached then
    return cached
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local discovery_key = backend
  local ranges = opts.cache ~= false and cache.get_ref(bufnr, "discovery", discovery_key, changedtick) or nil
  if not ranges then
    ranges = require("markdown-table-wrap.discovery").discover(
      bufnr,
      lines,
      { backend = backend ~= "default" and backend or nil }
    )
    if opts.cache ~= false then
      cache.set_ref(bufnr, "discovery", discovery_key, changedtick, ranges)
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
    if readonly then
      cache.set_ref(bufnr, "parse", cache_key, changedtick, tables)
    else
      cache.set(bufnr, "parse", cache_key, changedtick, tables)
    end
  end
  return tables
end

function M.parse_all(bufnr, opts)
  return parse_all(bufnr, opts, false)
end

-- Internal read-only adapter used by full-view construction. Public callers
-- keep the isolated-copy contract of parse_all().
function M.parse_all_ref(bufnr, opts)
  return parse_all(bufnr, opts, true)
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
