local M = {}
local logical_visuals = {}

local function set_unnamed(value)
  vim.fn.setreg('"', value, "c")
end

local function cancel_pending_operator()
  if vim.api.nvim_get_mode().mode:match("^no") then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end
end

local function cell_key(cell)
  if not cell or not cell.table_id or cell.row_index == nil or cell.column_index == nil then
    return nil
  end
  return table.concat({ cell.table_id, cell.row_index, cell.column_index }, ":")
end

local function rendered_cell_text(reader_bufnr, cell)
  local state = require("markdown-table-wrap.reader").get_state(reader_bufnr)
  local segments = state and state.cell_segments and state.cell_segments[cell_key(cell)] or nil
  if not segments or #segments == 0 then
    return cell.text or ""
  end

  local values = {}
  for _, item in ipairs(segments) do
    table.insert(values, item.cell and item.cell.text or "")
  end
  return table.concat(values, "\n")
end

function M.clear_visual(reader_bufnr)
  reader_bufnr = reader_bufnr or vim.api.nvim_get_current_buf()
  local previous = logical_visuals[reader_bufnr]
  logical_visuals[reader_bufnr] = nil
  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.b[reader_bufnr].markdown_table_wrap_cell_visual = nil
    if previous then
      require("markdown-table-wrap.mappings").restore(reader_bufnr, "y", "x", previous.mapping)
    end
  end
  return previous ~= nil
end

local function install_visual_yank(reader_bufnr, cell)
  M.clear_visual(reader_bufnr)
  logical_visuals[reader_bufnr] = {
    cell = vim.deepcopy(cell),
    mapping = require("markdown-table-wrap.mappings").get(reader_bufnr, "y", "x"),
  }
  vim.b[reader_bufnr].markdown_table_wrap_cell_visual = {
    table_id = cell.table_id,
    row_index = cell.row_index,
    column_index = cell.column_index,
  }
  vim.keymap.set("x", "y", function()
    M.visual_yank(reader_bufnr)
  end, {
    buffer = reader_bufnr,
    silent = true,
    nowait = true,
    desc = "Yank logical rendered Markdown table cell",
  })
end

local function notify(message, level)
  vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
end

local function reader_for(bufnr)
  local reader = require("markdown-table-wrap.reader")
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not reader.is_reader(bufnr) then
    return nil, "cell operations are available only in Reader mode"
  end
  return reader
end

local function current_cell(bufnr)
  local reader, err = reader_for(bufnr)
  if not reader then
    return nil, err
  end
  -- Reader line objects are derived data.  A Source edit from another window
  -- may have invalidated the current cell span before this mapping runs; make
  -- the projection current before resolving the logical cell.
  local source_bufnr = reader.source_bufnr(bufnr)
  local changedtick = reader.source_changedtick(bufnr)
  if source_bufnr and changedtick and vim.api.nvim_buf_is_valid(source_bufnr) then
    if changedtick ~= vim.api.nvim_buf_get_changedtick(source_bufnr) then
      if not reader.refresh(bufnr) then
        return nil, "the Reader projection could not be refreshed from Source"
      end
    end
  end
  local cell = reader.cell_at_cursor(bufnr)
  if not cell then
    return nil, "the cursor is not inside a rendered table cell"
  end
  if not cell.source_bufnr or not vim.api.nvim_buf_is_valid(cell.source_bufnr) then
    return nil, "the backing Source buffer is no longer valid"
  end
  if not cell.source_span then
    return nil, "the current cell has no Source range"
  end
  return cell, reader
end

function M.visual_yank(reader_bufnr)
  local session = logical_visuals[reader_bufnr]
  if not session then
    return false
  end

  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    M.clear_visual(reader_bufnr)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    return false
  end

  -- Keep the temporary Visual-mode y action tied to the cell that `vic`
  -- selected.  If the user moved across a border before yanking, silently
  -- copying the neighboring cell would be more surprising than cancelling
  -- the stale logical selection.
  if cell_key(session.cell) ~= cell_key(cell) then
    notify("the logical cell selection changed; press Esc and run vic again", vim.log.levels.WARN)
    M.clear_visual(reader_bufnr)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    return false
  end

  set_unnamed(rendered_cell_text(reader_bufnr, cell))
  vim.fn.setreg("0", vim.fn.getreg('"'), "c")
  reader_or_error.clear_visual_selection(reader_bufnr)
  M.clear_visual(reader_bufnr)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  return true
end

local function source_text(cell)
  local span = cell.source_span
  local lines = vim.api.nvim_buf_get_text(
    cell.source_bufnr,
    span.start_lnum - 1,
    span.start_col,
    span.end_lnum - 1,
    span.end_col,
    {}
  )
  return table.concat(lines, "\n")
end

local function normalize_single_line(value)
  value = type(value) == "string" and value or ""
  value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
  if value:find("\n", 1, true) then
    notify("cell content cannot contain a newline; line breaks were replaced with spaces.", vim.log.levels.WARN)
    value = value:gsub("\n", " ")
  end
  return value
end

local function replace_source(cell, value)
  local source_bufnr = cell.source_bufnr
  local span = cell.source_span
  if not vim.api.nvim_buf_is_valid(source_bufnr) then
    return false, "the backing Source buffer is no longer valid"
  end
  if not vim.bo[source_bufnr].modifiable then
    return false, "the backing Source buffer is not modifiable"
  end
  if vim.bo[source_bufnr].readonly then
    return false, "the backing Source buffer is read-only"
  end
  if cell.present == false then
    return false, "the current cell is missing from Source and cannot be edited safely"
  end
  if span.start_lnum ~= span.end_lnum then
    return false, "multi-line Source cells are not supported"
  end

  local ok, err = pcall(
    vim.api.nvim_buf_set_text,
    source_bufnr,
    span.start_lnum - 1,
    span.start_col,
    span.end_lnum - 1,
    span.end_col,
    {
      normalize_single_line(value),
    }
  )
  if not ok then
    return false, err
  end
  return true
end

local function refresh_cell(reader, reader_bufnr, cell)
  if not reader.refresh(reader_bufnr) then
    return false
  end
  reader.focus_source_cell(reader_bufnr, cell.source_span.start_lnum, cell.column_index, cell.table_id)
  return true
end

local function last_char_start(line, start_col, end_col)
  local col = math.max(start_col, end_col - 1)
  -- Reader columns are byte columns.  Walk back over UTF-8 continuation bytes
  -- so nvim_win_set_cursor always receives the beginning of the final cell
  -- character rather than the middle of a multibyte sequence.
  while col > start_col do
    local byte = line:byte(col + 1)
    if not byte or byte < 0x80 or byte > 0xBF then
      break
    end
    col = col - 1
  end
  return col
end

function M.yank(reader_bufnr)
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local value = source_text(cell)
  set_unnamed(value)
  vim.fn.setreg("0", value, "c")
  return true
end

function M.delete(reader_bufnr)
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local value = source_text(cell)
  local ok, err = replace_source(cell, "")
  if not ok then
    notify("could not delete cell: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  set_unnamed(value)
  return refresh_cell(reader_or_error, reader_bufnr, cell)
end

local function leave_reader_for_source(reader, reader_bufnr, cell, pause)
  local source_bufnr = reader.close(reader_bufnr)
  if not source_bufnr then
    notify("could not return to the backing Source buffer", vim.log.levels.ERROR)
    return nil
  end

  if pause then
    require("markdown-table-wrap").pause_buffer(source_bufnr)
  end
  vim.api.nvim_set_current_buf(source_bufnr)
  vim.api.nvim_win_set_cursor(0, { cell.source_span.start_lnum, cell.source_span.start_col })
  return source_bufnr
end

function M.change(reader_bufnr)
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local value = source_text(cell)
  local ok, err = replace_source(cell, "")
  if not ok then
    notify("could not change cell: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  set_unnamed(value)

  -- Cell change is a short Source editing hop, like Reader's i/a/o mappings;
  -- leave the Source unpaused so the normal auto-preview policy can recreate
  -- Reader after InsertLeave.
  local source_bufnr = leave_reader_for_source(reader_or_error, reader_bufnr, cell, false)
  if not source_bufnr then
    reader_or_error.refresh(reader_bufnr)
    return false
  end
  vim.cmd("startinsert")
  return true
end

function M.put(reader_bufnr)
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local value = vim.fn.getreg('"')
  if type(value) == "table" then
    value = table.concat(value, "\n")
  end
  local ok, err = replace_source(cell, value)
  if not ok then
    notify("could not put content into cell: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return refresh_cell(reader_or_error, reader_bufnr, cell)
end

function M.visual(reader_bufnr)
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local state = reader_or_error.get_state(reader_bufnr)
  local segments = state and state.cell_segments and state.cell_segments[cell_key(cell)] or nil
  local first = segments and segments[1] or nil
  local last = segments and segments[#segments] or nil
  local first_row = first and first.row or cell.render_start_row
  local first_col = first and first.cell.start_col or cell.render_start_col
  local last_row = last and last.row or cell.render_end_row
  local last_col_start = last and last.cell.start_col or cell.render_start_col
  local last_col_end = last and last.cell.end_col or cell.render_end_col

  local winid = cell.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    notify("the Reader window is no longer valid", vim.log.levels.ERROR)
    return false
  end

  vim.api.nvim_set_current_win(winid)
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[vV\22]") then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end
  vim.api.nvim_win_set_cursor(winid, { first_row, first_col })
  -- A logical cell may occupy several rendered rows.  Blockwise Visual keeps
  -- the selection constrained to the cell rectangle instead of selecting all
  -- columns on intermediate rows as charwise Visual would.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-v>", true, false, true), "nx", false)
  local end_line = vim.api.nvim_buf_get_lines(reader_bufnr, last_row - 1, last_row, false)[1] or ""
  vim.api.nvim_win_set_cursor(winid, {
    last_row,
    last_char_start(end_line, last_col_start, last_col_end),
  })
  install_visual_yank(reader_bufnr, cell)
  reader_or_error.update_visual_selection(reader_bufnr)
  return true
end

local function leave_and_invoke_fallback(reader, reader_bufnr, mapping)
  local position = reader.source_position(reader_bufnr)
  local source_bufnr = reader.source_bufnr(reader_bufnr)
  if not position or not source_bufnr then
    notify("the backing Source buffer is no longer available", vim.log.levels.ERROR)
    return false
  end
  if not reader.close(reader_bufnr) then
    return false
  end
  return require("markdown-table-wrap.mappings").invoke(mapping, {
    context_bufnr = source_bufnr,
    cursor = { position[2], position[3] },
  })
end

function M.change_or_fallback(reader_bufnr)
  local count = vim.v.count
  local cell = current_cell(reader_bufnr)
  if cell then
    return M.change(reader_bufnr)
  end

  local reader, err = reader_for(reader_bufnr)
  if not reader then
    notify(err, vim.log.levels.WARN)
    return false
  end
  local state = reader.get_state(reader_bufnr)
  local fallback = state and state.cell_fallbacks and state.cell_fallbacks.change or nil
  if fallback then
    return leave_and_invoke_fallback(reader, reader_bufnr, fallback)
  end

  local position = reader.source_position(reader_bufnr)
  local source_bufnr = reader.source_bufnr(reader_bufnr)
  if not position or not source_bufnr or not reader.close(reader_bufnr) then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { position[2], position[3] })
  vim.api.nvim_feedkeys((count > 0 and tostring(count) or "") .. "c", "n", false)
  return true
end

function M.install(map, reader_bufnr, state)
  local config = (((state.config or {}).mappings or {}).reader or {}).cell or {}
  if config.enabled == false then
    return
  end

  state.cell_fallbacks = {
    change = require("markdown-table-wrap.mappings").get(state.source_bufnr, "c", "n"),
  }

  local function install(lhs, callback, description, modes)
    map(lhs, callback, description, modes)
  end

  local function has_operator_prefix(lhs, operator)
    return type(lhs) == "string" and lhs:sub(1, 1) == operator and lhs:sub(2) ~= ""
  end

  local operator_text_objects = {}
  local function register_operator(lhs, operator, callback, description, cancel)
    if type(lhs) ~= "string" or lhs == "" then
      return
    end
    local suffix = lhs:sub(1, 1) == operator and lhs:sub(2) or nil
    if suffix and suffix ~= "" then
      operator_text_objects[suffix] = operator_text_objects[suffix] or {}
      operator_text_objects[suffix][operator] = { callback = callback, cancel = cancel }
    end
  end

  -- Do not install a complete Normal-mode mapping such as `yic` or `dic`.
  -- Vim's built-in y/d operators win the first keystroke and enter
  -- operator-pending mode, so the full mapping can appear in :map but never
  -- run for real keyboard input.  The text-object suffix mappings below are
  -- the canonical path; keep Normal mappings only for custom non-operator
  -- keys (or the contextual-c mapping aliases handled just below).
  if not has_operator_prefix(config.yank, "y") then
    install(config.yank, function()
      M.yank(reader_bufnr)
    end, "Yank current cell Source")
  end
  if not has_operator_prefix(config.visual, "v") then
    install(config.visual, function()
      M.visual(reader_bufnr)
    end, "Select current rendered cell")
  end
  if not has_operator_prefix(config.delete, "d") then
    install(config.delete, function()
      M.delete(reader_bufnr)
    end, "Delete current cell Source")
  end
  -- The contextual `c` mapping is itself buffer-local and therefore can
  -- disambiguate longer `cic`/`cip` aliases before invoking the built-in
  -- operator.  Keep those legacy Normal aliases for compatibility; the
  -- operator-pending handlers below remain available when users remap the
  -- contextual `c` key or disable it.
  install(config.change, function()
    M.change(reader_bufnr)
  end, "Change current cell Source")
  install(config.put, function()
    M.put(reader_bufnr)
  end, "Put register into current cell Source")
  install(config.change_operator, function()
    M.change_or_fallback(reader_bufnr)
  end, "Change current cell or delegate Source change")

  register_operator(config.yank, "y", function()
    return M.yank(reader_bufnr)
  end, "Yank current cell Source", true)
  register_operator(config.delete, "d", function()
    return M.delete(reader_bufnr)
  end, "Delete current cell Source", true)
  register_operator(config.change, "c", function()
    return M.change(reader_bufnr)
  end, "Change current cell Source", false)
  register_operator(config.put, "c", function()
    return M.put(reader_bufnr)
  end, "Put register into current cell Source", true)

  for suffix, handlers in pairs(operator_text_objects) do
    install(suffix, function()
      local operation = handlers[vim.v.operator]
      if not operation then
        cancel_pending_operator()
        return false
      end
      local ok = operation.callback()
      if operation.cancel then
        cancel_pending_operator()
      end
      return ok
    end, "Markdown table cell text object", "o")
  end

  local visual_suffix
  if type(config.visual) == "string" and config.visual:sub(1, 1) == "v" then
    visual_suffix = config.visual:sub(2)
  end
  if visual_suffix and visual_suffix ~= "" then
    install(visual_suffix, function()
      return M.visual(reader_bufnr)
    end, "Select current rendered cell", "x")
  end
end

return M
