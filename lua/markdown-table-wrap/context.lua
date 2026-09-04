local M = {}

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function resolve_window(bufnr, winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current) == bufnr then
    return current
  end
  return vim.fn.win_findbuf(bufnr)[1]
end

local function source_cursor(source_bufnr, view_bufnr, winid, mode)
  if mode == "reader" then
    local position = require("markdown-table-wrap.reader").source_position(view_bufnr, winid)
    if position then
      return { position[2], position[3] }
    end
  elseif mode == "float" then
    local plugin = require("markdown-table-wrap")
    local rendered = plugin.state.float_rendered
    local view_lnum = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_cursor(winid)[1] or 1
    local view_col = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_cursor(winid)[2] or 0
    local line_object = rendered and rendered.line_objects and rendered.line_objects[view_lnum] or nil
    for _, cell in ipairs(type(line_object) == "table" and line_object.cells or {}) do
      if view_col >= (cell.start_col or 0) and view_col < (cell.end_col or 0) and cell.source_span then
        return { cell.source_span.start_lnum, cell.source_span.start_col }
      end
    end
    if rendered and rendered.source_lnums then
      return { rendered.source_lnums[view_lnum] or rendered.start_lnum or 1, 0 }
    end
  end

  if winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == source_bufnr then
    return vim.api.nvim_win_get_cursor(winid)
  end
  return { 1, 0 }
end

local function cell_context(source_bufnr, cursor, table_info)
  if not table_info then
    return nil
  end

  local model_row
  if cursor[1] == table_info.start_lnum then
    model_row = table_info.header
  else
    for _, row in ipairs(table_info.rows or {}) do
      if row.source_lnum == cursor[1] then
        model_row = row
        break
      end
    end
  end
  for index, cell in ipairs(model_row or {}) do
    local span = cell.source_span
    if span and cursor[2] >= span.start_col and cursor[2] <= span.end_col then
      return {
        index = index,
        start_col = span.start_col,
        end_col = span.end_col,
        text = cell.text,
        source_span = span,
        table_id = table_info.id,
        row_index = cell.row_index,
        present = cell.present,
        tokens = cell.tokens,
        spans = cell.spans,
      }
    end
  end

  local line = vim.api.nvim_buf_get_lines(source_bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local spans = require("markdown-table-wrap.nav").spans(line)
  for index, span in ipairs(spans) do
    if cursor[2] >= span.start_col and cursor[2] <= span.end_col then
      return {
        index = index,
        start_col = span.start_col,
        end_col = span.end_col,
        text = vim.trim(line:sub(span.start_col + 1, span.end_col)),
      }
    end
  end
  return nil
end

local function supported_source(plugin, source_bufnr)
  local filetype = vim.bo[source_bufnr].filetype
  local supported = require("markdown-table-wrap.config").filetypes(plugin.config.extra_filetypes)
  return vim.tbl_contains(supported, filetype)
end

function M.resolve(opts)
  opts = opts or {}
  local view_bufnr = normalize_bufnr(opts.bufnr)
  if not vim.api.nvim_buf_is_valid(view_bufnr) then
    return nil, "the requested view buffer is no longer valid"
  end

  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")
  local mode = "source"
  local source_bufnr = view_bufnr

  if reader.is_reader(view_bufnr) then
    mode = "reader"
    source_bufnr = reader.source_bufnr(view_bufnr)
  elseif plugin.state.buf == view_bufnr and plugin.state.float_source_bufnr then
    mode = "float"
    source_bufnr = plugin.state.float_source_bufnr
  elseif inline.is_active(view_bufnr) then
    mode = "inline"
  end

  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    if mode == "reader" then
      reader.cleanup(view_bufnr)
    end
    return nil, "the backing Markdown Source buffer is no longer available"
  end
  if not supported_source(plugin, source_bufnr) then
    return nil, "the requested buffer is not a configured Markdown Source"
  end

  local winid = resolve_window(view_bufnr, opts.winid)
  local cursor = source_cursor(source_bufnr, view_bufnr, winid, mode)
  local table_info = nil
  local ok, parsed = pcall(require("markdown-table-wrap.parser").parse_at_cursor, source_bufnr, cursor[1])
  if ok then
    table_info = parsed
  end

  local path = vim.api.nvim_buf_get_name(source_bufnr)
  local config = plugin.get_buffer_config(source_bufnr)
  local cache_status = require("markdown-table-wrap.cache").inspect(source_bufnr)
  local discovery_status = require("markdown-table-wrap.discovery").status(source_bufnr)
  local excess_cells = 0
  for _, row in ipairs(table_info and table_info.rows or {}) do
    excess_cells = excess_cells + #(row.overflow_cells or {})
  end
  local context = {
    mode = mode,
    source_bufnr = source_bufnr,
    source_path = path ~= "" and path or nil,
    view_bufnr = view_bufnr,
    winid = winid,
    cursor = {
      source_lnum = cursor[1],
      source_col = cursor[2],
      view_lnum = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_cursor(winid)[1] or nil,
      view_col = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_cursor(winid)[2] or nil,
    },
    window = {
      width = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_width(winid) or nil,
      height = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_height(winid) or nil,
    },
    table = table_info and {
      start_lnum = table_info.start_lnum,
      separator_lnum = table_info.separator_lnum,
      end_lnum = table_info.end_lnum,
      columns = #table_info.header,
      excess_cells = excess_cells,
    } or nil,
    cell = cell_context(source_bufnr, cursor, table_info),
    config = config,
    cache = {
      changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr),
      rendered = plugin.state.last_signature[source_bufnr] ~= nil,
      paused = plugin.state.paused_buffers[source_bufnr] == true,
      auto_preview = config.auto_preview == true,
      enabled = cache_status.enabled,
      entries = cache_status.entries,
      stages = cache_status.stages,
      hits = cache_status.hits,
      misses = cache_status.misses,
      token_entries = cache_status.token_entries,
    },
    discovery = discovery_status,
  }

  if mode == "reader" then
    context.reader = reader.summary(view_bufnr)
  elseif mode == "inline" then
    context.inline = inline.get_state(source_bufnr)
  elseif mode == "float" then
    local rendered = plugin.state.float_rendered
    context.float = rendered
        and {
          width = rendered.width,
          height = rendered.height,
          start_lnum = rendered.start_lnum,
          end_lnum = rendered.end_lnum,
          source_winid = plugin.state.float_source_winid,
          source_alt_bufnr = plugin.state.float_source_alt_bufnr,
        }
      or nil
  end

  return context
end

function M.source_bufnr(bufnr)
  local context = M.resolve({ bufnr = bufnr })
  return context and context.source_bufnr or nil
end

return M
