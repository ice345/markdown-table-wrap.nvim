local markdown = require("markdown-table-wrap.markdown")
local parser = require("markdown-table-wrap.parser")
local render = require("markdown-table-wrap.render")

local M = {}

local function notify(message, level, opts)
  if not (opts or {}).silent then
    vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
  end
end

local function source_cell(cell, config)
  if not cell or cell.present == false then
    return ""
  end
  -- Copying is semantic rather than decorative: link/image icons belong to
  -- the view and should not leak into a clipboard value.
  return markdown.inline_to_text(cell.raw or cell.text or "")
end

local function current_context(opts)
  local context, err = require("markdown-table-wrap.context").resolve(opts or {})
  if not context then
    notify(err or "could not resolve the active Markdown Source", vim.log.levels.ERROR, opts)
  end
  return context
end

local function current_table(context, opts)
  opts = opts or {}
  local tables = parser.parse_all(context.source_bufnr, { cache = opts.cache ~= false })
  if opts.table_index then
    local index = tonumber(opts.table_index)
    return index and tables[index] or nil
  end
  if opts.table_id then
    for _, table_info in ipairs(tables) do
      if table_info.id == opts.table_id then
        return table_info
      end
    end
  end
  local lnum = context.cursor.source_lnum or 1
  for _, table_info in ipairs(tables) do
    if lnum >= table_info.start_lnum and lnum <= table_info.end_lnum then
      return table_info
    end
  end
  return nil
end

local function selected_tables(context, opts)
  opts = opts or {}
  local tables = parser.parse_all(context.source_bufnr, { cache = opts.cache ~= false })
  if opts.all then
    return tables
  end

  local first = tonumber(opts.start_lnum or opts.line_start)
  local last = tonumber(opts.end_lnum or opts.line_end)
  if first and last then
    local selected = {}
    for _, table_info in ipairs(tables) do
      if table_info.end_lnum >= first and table_info.start_lnum <= last then
        table.insert(selected, table_info)
      end
    end
    return selected
  end

  local table_info = current_table(context, opts)
  return table_info and { table_info } or {}
end

local function reader_cell_text(context)
  if context.mode ~= "reader" then
    return nil
  end
  local reader = require("markdown-table-wrap.reader")
  local cell = reader.cell_at_cursor(context.view_bufnr, context.winid)
  if not cell then
    return nil
  end
  local table_info = current_table(context, {})
  local source_cell_value = table_info
      and (cell.row_index == 0 and table_info.header[cell.column_index] or table_info.rows[cell.row_index] and table_info.rows[cell.row_index][cell.column_index])
    or nil
  if source_cell_value then
    return source_cell(source_cell_value, context.config), cell
  end

  local values = {}
  for _, item in ipairs(reader.cell_segments(context.view_bufnr, cell) or {}) do
    table.insert(values, item.cell.text or "")
  end
  return table.concat(values, "\n"), cell
end

local function set_register(value, opts)
  opts = opts or {}
  vim.fn.setreg('"', value, "v")
  vim.fn.setreg("0", value, "v")
  if opts.clipboard ~= false then
    pcall(vim.fn.setreg, "+", value, "v")
  end
end

local function copy_value(value, label, opts)
  if value == nil then
    notify("no " .. label .. " is available at the current position", vim.log.levels.INFO, opts)
    return false
  end
  set_register(value, opts)
  notify("copied " .. label, vim.log.levels.INFO, opts)
  return true, value
end

function M.cell(opts)
  opts = opts or {}
  local context = opts.context or current_context(opts)
  if not context then
    return false
  end

  local displayed = reader_cell_text(context)
  if displayed ~= nil then
    return copy_value(displayed, "rendered cell", opts)
  end

  if not context.cell or not context.table then
    return copy_value(nil, "rendered cell", opts)
  end
  local table_info = current_table(context, opts)
  local cell = table_info
    and (
      context.cell.row_index == 0 and table_info.header[context.cell.index]
      or table_info.rows[context.cell.row_index] and table_info.rows[context.cell.row_index][context.cell.index]
    )
  if not cell then
    return copy_value(nil, "rendered cell", opts)
  end
  return copy_value(source_cell(cell, context.config), "rendered cell", opts)
end

function M.table(opts)
  opts = opts or {}
  local context = opts.context or current_context(opts)
  if not context then
    return false
  end
  local table_info = current_table(context, opts)
  if not table_info then
    return copy_value(nil, "rendered table", opts)
  end

  local rendered
  if context.mode == "reader" then
    rendered = require("markdown-table-wrap.reader").rendered_table(context.view_bufnr, table_info.id)
  elseif context.mode == "float" then
    rendered = require("markdown-table-wrap").state.float_rendered
  end
  rendered = rendered or render.render_table(table_info, context.config)
  return copy_value(table.concat(rendered.lines or {}, "\n"), "rendered table", opts)
end

local function rows_for(table_info)
  local rows = { table_info.header }
  for _, row in ipairs(table_info.rows or {}) do
    table.insert(rows, row)
  end
  return rows
end

local function export_value(value, format)
  value = tostring(value or "")
  if format == "csv" then
    if value:find('[,"\r\n]') then
      return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
  end
  -- TSV has no universal quoting convention. Use the conventional C-style
  -- escapes so tabs/newlines cannot change the row/column structure.
  return value:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n")
end

function M.export(opts)
  opts = opts or {}
  local context = opts.context or current_context(opts)
  if not context then
    return false
  end
  local format = tostring(opts.format or "tsv"):lower()
  if format ~= "tsv" and format ~= "csv" then
    notify("export format must be tsv or csv", vim.log.levels.ERROR, opts)
    return false
  end
  local tables = selected_tables(context, opts)
  if #tables == 0 then
    notify("no Markdown table is available at the current position", vim.log.levels.INFO, opts)
    return false
  end

  local table_outputs = {}
  for _, table_info in ipairs(tables) do
    local row_outputs = {}
    for _, row in ipairs(rows_for(table_info)) do
      local values = {}
      for index = 1, #table_info.header do
        local value = export_value(source_cell(row[index], { link = {} }), format)
        table.insert(values, value)
      end
      table.insert(row_outputs, table.concat(values, format == "csv" and "," or "\t"))
    end
    table.insert(table_outputs, table.concat(row_outputs, "\n"))
  end

  local value = table.concat(table_outputs, "\n\n")
  set_register(value, opts)
  notify(
    string.format("exported %d table%s as %s", #tables, #tables == 1 and "" or "s", format:upper()),
    vim.log.levels.INFO,
    opts
  )
  return true, value
end

function M.names()
  return { "cell", "table", "export" }
end

return M
