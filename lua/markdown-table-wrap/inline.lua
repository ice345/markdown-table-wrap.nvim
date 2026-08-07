local render = require("markdown-table-wrap.render")

local M = {}

local namespace = vim.api.nvim_create_namespace("markdown-table-wrap")
local saved_conceallevels = {}
local saved_concealcursors = {}
local saved_wraps = {}
local active_buffers = {}
local active_tables = {}
local active_configs = {}
local view_offsets = {}

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local border_chars = {
  ["╭"] = true,
  ["╮"] = true,
  ["╰"] = true,
  ["╯"] = true,
  ["┌"] = true,
  ["┐"] = true,
  ["└"] = true,
  ["┘"] = true,
  ["┬"] = true,
  ["┴"] = true,
  ["├"] = true,
  ["┤"] = true,
  ["┼"] = true,
  ["│"] = true,
  ["─"] = true,
  ["+"] = true,
  ["|"] = true,
  ["-"] = true,
}

local function iter_chars(text)
  return (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function append_chunk(chunks, text, hl_group)
  if text == "" then
    return
  end

  local last = chunks[#chunks]
  if last and last[2] == hl_group then
    last[1] = last[1] .. text
  else
    table.insert(chunks, { text, hl_group })
  end
end

local function semantic_chunks(line, line_index, is_header)
  local chunks = {}
  local index = 1

  while index <= #line do
    local code_start = line:find("`", index, true)
    local link_start = line:find("%[.-%]%(.-%)", index)
    local special_start = nil
    local special_end = nil
    local special_hl = nil

    if code_start and (not link_start or code_start < link_start) then
      local code_end = line:find("`", code_start + 1, true)
      if code_end then
        special_start = code_start
        special_end = code_end
        special_hl = "MarkdownTableWrapCode"
      end
    elseif link_start then
      local start_col, end_col = line:find("%[.-%]%(.-%)", index)
      special_start = start_col
      special_end = end_col
      special_hl = "MarkdownTableWrapLink"
    end

    local plain_end = special_start and special_start - 1 or #line
    local plain = line:sub(index, plain_end)
    local buffer = ""
    for ch in iter_chars(plain) do
      local hl_group
      if border_chars[ch] then
        hl_group = "MarkdownTableWrapBorder"
      elseif is_header or line_index == 2 then
        hl_group = "MarkdownTableWrapHeader"
      else
        hl_group = "MarkdownTableWrapInline"
      end
      append_chunk(chunks, ch, hl_group)
      buffer = ""
    end

    if not special_start then
      break
    end

    append_chunk(chunks, line:sub(special_start, special_end), special_hl)
    index = special_end + 1
  end

  return chunks
end

local function chunks_from_line_object(line_obj, line_index)
  local is_header = type(line_obj) == "table" and line_obj.is_header == true
  if type(line_obj) ~= "table" or not line_obj.chunks or #line_obj.chunks == 0 then
    return semantic_chunks(type(line_obj) == "table" and line_obj.text or line_obj, line_index, is_header)
  end

  local result = {}
  local cursor = 0
  local sorted = vim.deepcopy(line_obj.chunks)
  table.sort(sorted, function(a, b)
    return a.start_col < b.start_col
  end)

  for _, styled in ipairs(sorted) do
    if cursor < styled.start_col then
      vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1, styled.start_col), line_index, is_header))
    end

    table.insert(result, {
      line_obj.text:sub(styled.start_col + 1, styled.end_col),
      styled.hl_group,
    })
    cursor = styled.end_col
  end

  if cursor < #line_obj.text then
    vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1), line_index, is_header))
  end

  return result
end

local function padded_chunks(line_obj, line_index, target_width)
  local line = type(line_obj) == "table" and line_obj.text or line_obj
  local chunks = chunks_from_line_object(line_obj, line_index)
  local missing = math.max(0, target_width - vim.api.nvim_strwidth(line))

  if missing > 0 then
    append_chunk(chunks, string.rep(" ", missing), "MarkdownTableWrapBlank")
  end

  return chunks
end

local function virt_lines(lines, start_index)
  local result = {}
  start_index = start_index or 1

  for index, line in ipairs(lines) do
    table.insert(result, chunks_from_line_object(line, start_index + index - 1))
  end

  return result
end

local function ensure_highlights(config)
  require("markdown-table-wrap.theme").apply(config)
end

local function cursor_in_tables(winid, tables)
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local cursor_lnum = vim.api.nvim_win_get_cursor(winid)[1]
  for _, table_info in ipairs(tables or {}) do
    if cursor_lnum >= table_info.start_lnum and cursor_lnum <= table_info.end_lnum then
      return true
    end
  end

  return false
end

local function should_disable_wrap(config, in_table)
  if config.inline_mode ~= "replace" or config.inline_disable_wrap == false then
    return false
  end

  if config.inline_wrap_scope == "never" then
    return false
  end

  if config.inline_wrap_scope == "cursor" then
    return in_table
  end

  return true
end

local function restore_saved_wrap(winid)
  local previous_wrap = saved_wraps[winid]
  if previous_wrap ~= nil and vim.api.nvim_win_is_valid(winid) then
    if vim.wo[winid].wrap ~= previous_wrap then
      vim.wo[winid].wrap = previous_wrap
    end
  end
  saved_wraps[winid] = nil
end

local function set_render_window(winid, config, in_table)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local current = vim.wo[winid].conceallevel
  if current < 2 then
    if saved_conceallevels[winid] == nil then
      saved_conceallevels[winid] = current
    end
    vim.wo[winid].conceallevel = 2
  end

  if saved_concealcursors[winid] == nil then
    saved_concealcursors[winid] = vim.wo[winid].concealcursor
  end
  vim.wo[winid].concealcursor = "nvc"

  if should_disable_wrap(config, in_table) then
    if saved_wraps[winid] == nil then
      saved_wraps[winid] = vim.wo[winid].wrap
    end
    if vim.wo[winid].wrap then
      vim.wo[winid].wrap = false
    end
  else
    restore_saved_wrap(winid)
  end
end

local function set_render_for_buffer(bufnr, config)
  local tables = active_tables[bufnr] or {}
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    set_render_window(winid, config, cursor_in_tables(winid, tables))
  end
end

local function restore_render_window(winid)
  local previous = saved_conceallevels[winid]
  if previous ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].conceallevel = previous
  end
  saved_conceallevels[winid] = nil

  local previous_cursor = saved_concealcursors[winid]
  if previous_cursor ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].concealcursor = previous_cursor
  end
  saved_concealcursors[winid] = nil

  restore_saved_wrap(winid)
end

local function restore_render_for_buffer(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    restore_render_window(winid)
  end
end

local function conceal_source_line(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  if line == "" then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
    end_row = row,
    end_col = #line,
    conceal = "",
    priority = 9999,
  })
end

local function table_key(table_info)
  return tostring(table_info.start_lnum) .. ":" .. tostring(table_info.end_lnum)
end

local function view_offset(bufnr, table_info, source_count, rendered_count, config)
  if not config.inline_viewport_scrolling then
    return 0
  end

  view_offsets[bufnr] = view_offsets[bufnr] or {}
  local key = table_key(table_info)
  local max_offset = math.max(0, rendered_count - source_count)
  local offset = math.max(0, math.min(view_offsets[bufnr][key] or 0, max_offset))
  view_offsets[bufnr][key] = offset
  return offset
end

local function show_replace(bufnr, table_info, config, rendered)
  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  local rendered_count = #rendered.lines
  local first_rendered = view_offset(bufnr, table_info, source_count, rendered_count, config)
  local overlay_count = math.min(source_count, rendered_count - first_rendered)
  local start_row = table_info.start_lnum - 1
  local overlay_width = rendered.width
  if config.overlay_fill then
    overlay_width = vim.api.nvim_win_get_width(0)
  end
  local priority = config.overlay_priority or 10000

  for source_offset = 0, source_count - 1 do
    conceal_source_line(bufnr, start_row + source_offset)
  end

  for source_offset = 0, overlay_count - 1 do
    local line_obj = (rendered.line_objects or rendered.lines)[first_rendered + source_offset + 1]
    local mark = {
      virt_text = padded_chunks(line_obj, first_rendered + source_offset + 1, overlay_width),
      hl_mode = "replace",
      right_gravity = false,
      priority = priority,
    }

    if config.inline_virtual_text == "win_col" then
      mark.virt_text_win_col = 0
    else
      mark.virt_text_pos = "overlay"
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row + source_offset, 0, mark)
  end

  if rendered_count > overlay_count and not config.inline_viewport_scrolling then
    local extra = {}
    for index = overlay_count + 1, rendered_count do
      table.insert(extra, (rendered.line_objects or rendered.lines)[index])
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, table_info.end_lnum - 1, 0, {
      virt_lines = virt_lines(extra, overlay_count + 1),
      virt_lines_above = false,
      right_gravity = false,
      priority = priority,
    })
  end
end

local function show_insert(bufnr, table_info, config, rendered)
  local target_line = math.max(table_info.start_lnum - 1, 0)
  local above = config.inline_position ~= "below"

  vim.api.nvim_buf_set_extmark(bufnr, namespace, target_line, 0, {
    virt_lines = virt_lines(rendered.line_objects or rendered.lines),
    virt_lines_above = above,
    right_gravity = false,
    priority = 200,
  })

  if config.dim_source ~= false then
    for line = table_info.start_lnum - 1, table_info.end_lnum - 1 do
      vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, {
        line_hl_group = "MarkdownTableWrapSource",
        priority = 100,
      })
    end
  end
end

function M.clear(bufnr)
  bufnr = normalize_bufnr(bufnr)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end

  active_buffers[bufnr] = nil
  active_tables[bufnr] = nil
  active_configs[bufnr] = nil
  restore_render_for_buffer(bufnr)
end

function M.detach_window(winid)
  winid = winid or vim.api.nvim_get_current_win()
  restore_render_window(winid)
end

function M.dispose(bufnr)
  bufnr = normalize_bufnr(bufnr)
  M.clear(bufnr)
  view_offsets[bufnr] = nil
end

function M.reset_view(bufnr)
  bufnr = normalize_bufnr(bufnr)
  view_offsets[bufnr] = nil
end

function M.is_active(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
  return #marks > 0
end

local function show_one(bufnr, table_info, config)
  local rendered = render.render_table(table_info, config)

  if config.inline_mode == "insert" then
    show_insert(bufnr, table_info, config, rendered)
  else
    show_replace(bufnr, table_info, config, rendered)
  end

  return rendered
end

function M.show(bufnr, table_info, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered = show_one(bufnr, table_info, config)
  active_buffers[bufnr] = true
  active_tables[bufnr] = { table_info }
  active_configs[bufnr] = config
  if config.inline_mode == "replace" then
    set_render_for_buffer(bufnr, config)
  end
  return rendered
end

function M.show_many(bufnr, tables, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered = {}
  for _, table_info in ipairs(tables) do
    table.insert(rendered, show_one(bufnr, table_info, config))
  end

  active_buffers[bufnr] = #tables > 0
  active_tables[bufnr] = tables
  active_configs[bufnr] = config
  if config.inline_mode == "replace" then
    set_render_for_buffer(bufnr, config)
  end
  return rendered
end

local function table_under_cursor(bufnr, tables)
  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, table_info in ipairs(tables) do
    if cursor_lnum >= table_info.start_lnum and cursor_lnum <= table_info.end_lnum then
      return table_info
    end
  end
  return nil
end

local function max_view_offset(table_info, config)
  local rendered = render.render_table(table_info, config)
  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  return math.max(0, #rendered.lines - source_count)
end

function M.scroll(bufnr, delta)
  bufnr = normalize_bufnr(bufnr)
  local tables = active_tables[bufnr]
  local config = active_configs[bufnr]
  if not tables or not config or not config.inline_viewport_scrolling then
    return false
  end

  local target = table_under_cursor(bufnr, tables)
  if not target then
    return false
  end

  local max_offset = max_view_offset(target, config)
  if max_offset == 0 then
    return false
  end

  view_offsets[bufnr] = view_offsets[bufnr] or {}
  local key = table_key(target)
  local current = view_offsets[bufnr][key] or 0
  local next_offset = math.max(0, math.min(current + delta, max_offset))
  if next_offset == current then
    return true
  end

  view_offsets[bufnr][key] = next_offset
  M.show_many(bufnr, tables, config)
  return true
end

function M.scroll_to(bufnr, position)
  bufnr = normalize_bufnr(bufnr)
  local tables = active_tables[bufnr]
  local config = active_configs[bufnr]
  if not tables or not config or not config.inline_viewport_scrolling then
    return false
  end

  local target = table_under_cursor(bufnr, tables)
  if not target then
    return false
  end

  local max_offset = max_view_offset(target, config)
  view_offsets[bufnr] = view_offsets[bufnr] or {}
  view_offsets[bufnr][table_key(target)] = position == "bottom" and max_offset or 0
  M.show_many(bufnr, tables, config)
  return true
end

function M.attach_window(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if active_buffers[bufnr] and (active_configs[bufnr] or {}).inline_mode == "replace" then
    set_render_for_buffer(bufnr, active_configs[bufnr] or {})
  end
end

function M.update_wrap_for_cursor(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not active_buffers[bufnr] then
    return false
  end

  local config = active_configs[bufnr] or {}
  if config.inline_mode ~= "replace" then
    return false
  end

  set_render_for_buffer(bufnr, config)
  return true
end

function M.get_state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not active_buffers[bufnr] then
    return nil
  end

  return {
    tables = vim.deepcopy(active_tables[bufnr] or {}),
    config = vim.deepcopy(active_configs[bufnr] or {}),
    view_offsets = vim.deepcopy(view_offsets[bufnr] or {}),
  }
end

function M.namespace()
  return namespace
end

return M
