local M = {}
local logical_visuals = {}
local last_changes = {}
local pending_changes = {}
local repeat_namespace = vim.api.nvim_create_namespace("markdown-table-wrap-cell-repeat")
local visual_operators = { "y", "d", "c", "p", "P" }

local function exit_visual_mode()
  if vim.api.nvim_get_mode().mode:match("^[vV\22]") then
    vim.cmd("normal! \27")
  end
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

function M.clear_visual(reader_bufnr)
  reader_bufnr = reader_bufnr or vim.api.nvim_get_current_buf()
  local previous = logical_visuals[reader_bufnr]
  logical_visuals[reader_bufnr] = nil
  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.b[reader_bufnr].markdown_table_wrap_cell_visual = nil
    if previous then
      for lhs, mapping in pairs(previous.mappings or {}) do
        require("markdown-table-wrap.mappings").restore(reader_bufnr, lhs, "x", mapping)
      end
    end
  end
  return previous ~= nil
end

local function install_visual_operators(reader_bufnr, cell)
  M.clear_visual(reader_bufnr)
  local session = {
    cell = vim.deepcopy(cell),
    mappings = {},
  }
  logical_visuals[reader_bufnr] = session
  vim.b[reader_bufnr].markdown_table_wrap_cell_visual = {
    table_id = cell.table_id,
    row_index = cell.row_index,
    column_index = cell.column_index,
  }
  for _, operator in ipairs(visual_operators) do
    local lhs = operator
    session.mappings[lhs] = require("markdown-table-wrap.mappings").get(reader_bufnr, lhs, "x")
    vim.keymap.set("x", lhs, function()
      M.visual_operator(reader_bufnr, lhs)
    end, {
      buffer = reader_bufnr,
      silent = true,
      nowait = true,
      desc = "Apply " .. lhs .. " to logical Markdown table cell Source",
    })
  end
end

local function notify(message, level)
  vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
end

local function selected_register(opts)
  local register = opts and opts.register or '"'
  if type(register) ~= "string" or #register ~= 1 then
    return '"'
  end
  return register
end

local function mapping_options()
  return { register = vim.v.register, count = vim.v.count }
end

local function visual_mapping_options()
  -- A count typed before `v` is consumed by the Visual command before the
  -- `ic` suffix mapping runs. Neovim retains it in v:prevcount; a count typed
  -- after `v` remains in v:count.
  local count = vim.v.count
  if count == 0 then
    count = vim.v.prevcount
  end
  return { register = vim.v.register, count = count }
end

local function mapping_characters(mapping, depth)
  if type(mapping) ~= "string" or mapping == "" then
    return nil
  end
  depth = depth or 0
  if depth > 4 then
    return nil
  end

  local characters = {}
  while mapping ~= "" do
    local lower = mapping:lower()
    local leader_token
    local leader
    if lower:sub(1, 8) == "<leader>" then
      leader_token = mapping:sub(1, 8)
      leader = vim.g.mapleader
    elseif lower:sub(1, 13) == "<localleader>" then
      leader_token = mapping:sub(1, 13)
      leader = vim.g.maplocalleader
    end
    if leader_token then
      leader = type(leader) == "string" and leader ~= "" and leader or "\\"
      local expanded = mapping_characters(leader, depth + 1)
      if not expanded then
        return nil
      end
      vim.list_extend(characters, expanded)
      mapping = mapping:sub(#leader_token + 1)
    else
      local token = mapping:match("^<[^>]+>")
      if token then
        table.insert(characters, vim.api.nvim_replace_termcodes(token, true, true, true))
        mapping = mapping:sub(#token + 1)
      else
        local character = vim.fn.strcharpart(mapping, 0, 1)
        if character == "" then
          return nil
        end
        table.insert(characters, character)
        mapping = mapping:sub(#character + 1)
      end
    end
  end
  return #characters > 0 and characters or nil
end

local function is_cancel_key(key)
  return key == vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    or key == vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
end

local function discard_pending_input()
  -- A complete mistyped motion may already be queued (for example `yap` or a
  -- macro containing `djP`). Once the guarded operator is rejected, executing
  -- that tail as unrelated Normal commands could still move the cursor or hit
  -- another non-modifiable-buffer error. Match Vim's error behavior by
  -- discarding the input that was already queued at the cancellation point.
  while true do
    local ok, key = pcall(vim.fn.getcharstr, 0)
    if not ok or key == "" or is_cancel_key(key) then
      return
    end
  end
end

local function guarded_cell_operator(lhs, operator, callback)
  if type(lhs) ~= "string" or lhs:sub(1, 1) ~= operator then
    return nil
  end
  local expected = mapping_characters(lhs:sub(2))
  if not expected then
    return nil
  end

  return function()
    -- Capture v:register/v:count before getcharstr() consumes the suffix. This
    -- keeps prefixes such as `"ayic` and `2yic` identical to native operator
    -- prefixes while preventing a mistyped motion from ever reaching the
    -- non-modifiable rendered Reader buffer.
    local opts = mapping_options()
    for _, expected_key in ipairs(expected) do
      local ok, key = pcall(vim.fn.getcharstr)
      if not ok or is_cancel_key(key) then
        return false
      end
      if key ~= expected_key then
        discard_pending_input()
        notify(
          string.format(
            "Reader %s accepts only %s for a Source cell; the incomplete operation was cancelled",
            operator,
            lhs
          ),
          vim.log.levels.WARN
        )
        return false
      end
    end
    return callback(opts)
  end
end

local function writable_register(register)
  return register:match('^[%w"*+_-]$') ~= nil
end

local function register_prefix(register)
  return register == '"' and "" or ('"' .. register)
end

local function count_is_supported(operation, opts)
  local count = opts and opts.count
  if count == nil then
    count = 0
  end
  count = tonumber(count) or 0
  if count <= 1 then
    return true
  end
  notify(operation .. " does not support a count yet; no cells were changed", vim.log.levels.WARN)
  return false
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

local function selected_visual_cell(reader_bufnr)
  local session = logical_visuals[reader_bufnr]
  if not session then
    return nil
  end

  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    M.clear_visual(reader_bufnr)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    return nil
  end

  -- Keep the temporary Visual-mode y action tied to the cell that `vic`
  -- selected.  If the user moved across a border before yanking, silently
  -- copying the neighboring cell would be more surprising than cancelling
  -- the stale logical selection.
  if cell_key(session.cell) ~= cell_key(cell) then
    notify("the logical cell selection changed; press Esc and run vic again", vim.log.levels.WARN)
    M.clear_visual(reader_bufnr)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    return nil
  end

  return cell, reader_or_error
end

local function leave_visual_cell(reader_bufnr, reader)
  reader.clear_visual_selection(reader_bufnr)
  M.clear_visual(reader_bufnr)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
end

function M.visual_operator(reader_bufnr, operator)
  local register = selected_register({ register = vim.v.register })
  local cell, reader = selected_visual_cell(reader_bufnr)
  if not cell then
    return false
  end

  leave_visual_cell(reader_bufnr, reader)
  local opts = { register = register, count = 1 }
  if operator == "y" then
    return M.yank(reader_bufnr, opts)
  elseif operator == "d" then
    return M.delete(reader_bufnr, opts)
  elseif operator == "c" then
    return M.change(reader_bufnr, opts)
  elseif operator == "p" or operator == "P" then
    return M.put(reader_bufnr, opts)
  end
  return false
end

function M.visual_yank(reader_bufnr)
  return M.visual_operator(reader_bufnr, "y")
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

local function validate_source(cell, expected_changedtick, read_only_ok)
  local source_bufnr = cell.source_bufnr
  local span = cell.source_span
  if not vim.api.nvim_buf_is_valid(source_bufnr) then
    return false, "the backing Source buffer is no longer valid"
  end
  if not read_only_ok and not vim.bo[source_bufnr].modifiable then
    return false, "the backing Source buffer is not modifiable"
  end
  if not read_only_ok and vim.bo[source_bufnr].readonly then
    return false, "the backing Source buffer is read-only"
  end
  if cell.present == false then
    return false, "the current cell is missing from Source and cannot be edited safely"
  end
  if span.start_lnum ~= span.end_lnum then
    return false, "multi-line Source cells are not supported"
  end
  if expected_changedtick and vim.api.nvim_buf_get_changedtick(source_bufnr) ~= expected_changedtick then
    return false, "the backing Source changed while leaving Reader"
  end

  return true
end

local function refresh_cell(reader, reader_bufnr, cell)
  if not reader.refresh(reader_bufnr) then
    return false
  end
  reader.focus_source_cell(reader_bufnr, cell.source_span.start_lnum, cell.column_index, cell.table_id, cell.row_index)
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

local function span_is_empty(cell)
  local span = cell.source_span
  return span.start_lnum == span.end_lnum and span.start_col == span.end_col
end

local function select_source_span(cell)
  if span_is_empty(cell) then
    vim.api.nvim_win_set_cursor(0, { cell.source_span.start_lnum, cell.source_span.start_col })
    return false
  end

  local span = cell.source_span
  local line = vim.api.nvim_buf_get_lines(cell.source_bufnr, span.end_lnum - 1, span.end_lnum, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { span.start_lnum, span.start_col })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { span.end_lnum, last_char_start(line, span.start_col, span.end_col) })
  return true
end

local function native_source_operator(cell, operator, register)
  if not writable_register(register) then
    return false, "register " .. vim.inspect(register) .. " cannot receive cell text"
  end

  local valid, validation_error = validate_source(cell, nil, operator == "y")
  if not valid then
    return false, validation_error
  end
  if span_is_empty(cell) then
    return true
  end

  cancel_pending_operator()
  local ok, err = pcall(vim.api.nvim_buf_call, cell.source_bufnr, function()
    select_source_span(cell)
    vim.cmd("normal! " .. register_prefix(register) .. operator)
  end)
  if not ok then
    return false, err
  end
  return true
end

local function undo_sequence(source_bufnr)
  if not vim.api.nvim_buf_is_valid(source_bufnr) then
    return nil
  end
  local ok, tree = pcall(vim.api.nvim_buf_call, source_bufnr, function()
    return vim.fn.undotree()
  end)
  return ok and type(tree) == "table" and tonumber(tree.seq_cur) or nil
end

local function remember_change(source_bufnr, change)
  if not vim.api.nvim_buf_is_valid(source_bufnr) then
    return
  end
  change.changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr)
  change.undo_sequence = undo_sequence(source_bufnr)
  last_changes[source_bufnr] = change
end

local function clear_pending_change(source_bufnr)
  local pending = pending_changes[source_bufnr]
  pending_changes[source_bufnr] = nil
  if pending and pending.autocmd then
    pcall(vim.api.nvim_del_autocmd, pending.autocmd)
  end
  if vim.api.nvim_buf_is_valid(source_bufnr) then
    vim.api.nvim_buf_clear_namespace(source_bufnr, repeat_namespace, 0, -1)
  end
end

local function finish_pending_change(source_bufnr)
  local pending = pending_changes[source_bufnr]
  if not pending or not vim.api.nvim_buf_is_valid(source_bufnr) then
    clear_pending_change(source_bufnr)
    return
  end

  local start_position = vim.api.nvim_buf_get_extmark_by_id(source_bufnr, repeat_namespace, pending.start_mark, {})
  local end_position = vim.api.nvim_buf_get_extmark_by_id(source_bufnr, repeat_namespace, pending.end_mark, {})
  if #start_position == 2 and #end_position == 2 then
    local lines = vim.api.nvim_buf_get_text(
      source_bufnr,
      start_position[1],
      start_position[2],
      end_position[1],
      end_position[2],
      {}
    )
    remember_change(source_bufnr, {
      kind = "change",
      register = pending.register,
      value = table.concat(lines, "\n"),
    })
  end
  clear_pending_change(source_bufnr)
end

local function prepare_change_repeat(cell, register)
  local source_bufnr = cell.source_bufnr
  local span = cell.source_span
  clear_pending_change(source_bufnr)
  local pending = {
    register = register,
    start_mark = vim.api.nvim_buf_set_extmark(source_bufnr, repeat_namespace, span.start_lnum - 1, span.start_col, {
      right_gravity = false,
    }),
    end_mark = vim.api.nvim_buf_set_extmark(source_bufnr, repeat_namespace, span.end_lnum - 1, span.end_col, {
      right_gravity = true,
    }),
  }
  pending_changes[source_bufnr] = pending
  pending.autocmd = vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = source_bufnr,
    once = true,
    callback = function()
      finish_pending_change(source_bufnr)
    end,
  })
end

local function replace_cell(cell, value, delete_register)
  local valid, validation_error = validate_source(cell)
  if not valid then
    return false, validation_error
  end
  if not writable_register(delete_register) then
    return false, "register " .. vim.inspect(delete_register) .. " cannot receive deleted cell text"
  end

  value = normalize_single_line(value)
  cancel_pending_operator()
  local ok, err = pcall(vim.api.nvim_buf_call, cell.source_bufnr, function()
    local selected = select_source_span(cell)
    if selected then
      vim.cmd("normal! " .. register_prefix(delete_register) .. "d")
    end
    if value ~= "" then
      if selected then
        vim.cmd("undojoin")
      end
      local span = cell.source_span
      vim.api.nvim_buf_set_text(
        cell.source_bufnr,
        span.start_lnum - 1,
        span.start_col,
        span.start_lnum - 1,
        span.start_col,
        { value }
      )
    end
  end)
  if not ok then
    return false, err
  end
  return true
end

function M.yank(reader_bufnr, opts)
  opts = opts or {}
  if not count_is_supported("yic", opts) then
    return false
  end
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local ok, err = native_source_operator(cell, "y", selected_register(opts))
  if not ok then
    notify("could not yank cell: " .. tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

function M.delete(reader_bufnr, opts)
  opts = opts or {}
  if not count_is_supported("dic", opts) then
    return false
  end
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local register = selected_register(opts)
  local ok, err = native_source_operator(cell, "d", register)
  if not ok then
    notify("could not delete cell: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  remember_change(cell.source_bufnr, { kind = "delete", register = register })
  return refresh_cell(reader_or_error, reader_bufnr, cell)
end

local function leave_reader_for_source(reader, reader_bufnr, cell, pause)
  local closed, source_bufnr = pcall(reader.close, reader_bufnr)
  if not closed then
    notify("could not return to the backing Source buffer: " .. tostring(source_bufnr), vim.log.levels.ERROR)
    return nil
  end
  if not source_bufnr then
    notify("could not return to the backing Source buffer", vim.log.levels.ERROR)
    return nil
  end

  local positioned, position_error = pcall(function()
    if pause then
      require("markdown-table-wrap").pause_buffer(source_bufnr)
    end
    vim.api.nvim_set_current_buf(source_bufnr)
    vim.api.nvim_win_set_cursor(0, { cell.source_span.start_lnum, cell.source_span.start_col })
  end)
  if not positioned then
    notify("could not position the backing Source buffer: " .. tostring(position_error), vim.log.levels.ERROR)
    return nil
  end
  return source_bufnr
end

function M.change(reader_bufnr, opts)
  opts = opts or {}
  if not count_is_supported("cic", opts) then
    return false
  end
  local register = selected_register(opts)
  if not writable_register(register) then
    notify("could not change cell: register " .. vim.inspect(register) .. " is not writable", vim.log.levels.ERROR)
    return false
  end
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local valid, validation_error = validate_source(cell)
  if not valid then
    notify("could not change cell: " .. tostring(validation_error), vim.log.levels.ERROR)
    return false
  end

  local source_changedtick = vim.api.nvim_buf_get_changedtick(cell.source_bufnr)
  cancel_pending_operator()

  -- Cell change is a short Source editing hop, like Reader's i/a/o mappings;
  -- leave the Source unpaused so the normal auto-preview policy can recreate
  -- Reader after InsertLeave.  Complete that transition before mutating Source:
  -- a user autocmd may refuse BufLeave, and a failed transition must leave the
  -- canonical Markdown and registers untouched.
  local source_bufnr = leave_reader_for_source(reader_or_error, reader_bufnr, cell, false)
  if not source_bufnr then
    return false
  end

  valid, validation_error = validate_source(cell, source_changedtick)
  if not valid then
    notify("could not change cell: " .. tostring(validation_error), vim.log.levels.ERROR)
    return false
  end

  prepare_change_repeat(cell, register)
  local selected = select_source_span(cell)
  vim.fn.feedkeys(selected and (register_prefix(register) .. "c") or "i", "in")
  return true
end

function M.put(reader_bufnr, opts)
  opts = opts or {}
  if not count_is_supported("cell put", opts) then
    return false
  end
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local register = selected_register(opts)
  local value = vim.fn.getreg(register)
  if type(value) == "table" then
    value = table.concat(value, "\n")
  end
  value = normalize_single_line(value)
  local ok, err = replace_cell(cell, value, '"')
  if not ok then
    notify("could not put content into cell: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  remember_change(cell.source_bufnr, { kind = "put", register = register, value = value })
  return refresh_cell(reader_or_error, reader_bufnr, cell)
end

function M.visual(reader_bufnr, opts)
  opts = opts or {}
  if not count_is_supported("vic", opts) then
    exit_visual_mode()
    return false
  end
  local cell, reader_or_error = current_cell(reader_bufnr)
  if not cell then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local segments = reader_or_error.cell_segments(reader_bufnr, cell)
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
    exit_visual_mode()
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
  install_visual_operators(reader_bufnr, cell)
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

local function leave_and_feed_native(reader, reader_bufnr, keys)
  local position = reader.source_position(reader_bufnr)
  local source_bufnr = reader.source_bufnr(reader_bufnr)
  if not position or not source_bufnr or not reader.close(reader_bufnr) then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { position[2], position[3] })
  vim.fn.feedkeys(keys, "in")
  return true
end

function M.repeat_last(reader_bufnr)
  local count = vim.v.count
  local cell, reader_or_error = current_cell(reader_bufnr)
  local reader = cell and reader_or_error or reader_for(reader_bufnr)
  if not reader then
    notify(reader_or_error, vim.log.levels.WARN)
    return false
  end

  local source_bufnr = reader.source_bufnr(reader_bufnr)
  local change = source_bufnr and last_changes[source_bufnr] or nil
  if change and vim.api.nvim_buf_get_changedtick(source_bufnr) ~= change.changedtick then
    -- Undo followed by redo returns to the same undo sequence even though the
    -- buffer changedtick is new. Keep logical cell repeat in that one safe
    -- case; unrelated edits and an undo without redo still invalidate it.
    if change.undo_sequence and undo_sequence(source_bufnr) == change.undo_sequence then
      change.changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr)
    else
      last_changes[source_bufnr] = nil
      change = nil
    end
  end

  if not cell or not change then
    local fallback = reader.mapping_fallback(reader_bufnr, "cell", "repeat_change")
    if fallback then
      return leave_and_invoke_fallback(reader, reader_bufnr, fallback)
    end
    return leave_and_feed_native(reader, reader_bufnr, (count > 0 and tostring(count) or "") .. ".")
  end

  if not count_is_supported("cell repeat", { count = count }) then
    return false
  end
  if change.kind == "delete" then
    return M.delete(reader_bufnr, { register = change.register, count = 1 })
  end

  local delete_register = change.kind == "change" and change.register or '"'
  local ok, err = replace_cell(cell, change.value or "", delete_register)
  if not ok then
    notify("could not repeat cell change: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  remember_change(source_bufnr, {
    kind = change.kind,
    register = change.register,
    value = change.value,
  })
  return refresh_cell(reader, reader_bufnr, cell)
end

function M.change_or_fallback(reader_bufnr)
  local opts = mapping_options()
  local count = opts.count
  local reader, err = reader_for(reader_bufnr)
  if not reader then
    notify(err, vim.log.levels.WARN)
    return false
  end
  local fallback = reader.mapping_fallback(reader_bufnr, "cell", "change")
  if fallback then
    return leave_and_invoke_fallback(reader, reader_bufnr, fallback)
  end

  local position = reader.source_position(reader_bufnr)
  local source_bufnr = reader.source_bufnr(reader_bufnr)
  if not position or not source_bufnr or not reader.close(reader_bufnr) then
    return false
  end
  vim.api.nvim_win_set_cursor(0, { position[2], position[3] })
  -- The complete `cic` mapping is resolved before this shorter `c` proxy. For
  -- every other motion, leave Reader and prepend the native operator so keys
  -- already in typeahead (for example `ip` in `cip`) continue in Source.
  local keys = register_prefix(selected_register(opts)) .. (count > 0 and tostring(count) or "") .. "c"
  vim.fn.feedkeys(keys, "in")
  return true
end

function M.install(map, reader_bufnr, state)
  local config = (((state.config or {}).mappings or {}).reader or {}).cell or {}
  if config.enabled == false then
    return
  end

  state.cell_fallbacks = {
    change = require("markdown-table-wrap.mappings").get(state.source_bufnr, "c", "n"),
    repeat_change = require("markdown-table-wrap.mappings").get(state.source_bufnr, ".", "n"),
  }

  local function install(lhs, callback, description, modes)
    map(lhs, callback, description, modes)
  end

  local function has_operator_prefix(lhs, operator)
    return type(lhs) == "string" and lhs:sub(1, 1) == operator and lhs:sub(2) ~= ""
  end

  local operator_text_objects = {}
  local function register_operator(lhs, operator, callback, description)
    if type(lhs) ~= "string" or lhs == "" then
      return
    end
    local suffix = lhs:sub(1, 1) == operator and lhs:sub(2) or nil
    if suffix and suffix ~= "" then
      operator_text_objects[suffix] = operator_text_objects[suffix] or {}
      operator_text_objects[suffix][operator] = { callback = callback }
    end
  end

  -- Reader is a derived, non-modifiable projection. Letting native y/d enter
  -- operator-pending mode would make a typo such as yj copy rendered borders,
  -- while dj would raise E21. For operator-prefixed cell mappings,
  -- claim the first key and synchronously accept only the configured suffix.
  -- Esc or any mismatch cancels without touching registers, Source, or Reader.
  local guarded_yank = guarded_cell_operator(config.yank, "y", function(opts)
    return M.yank(reader_bufnr, opts)
  end)
  local guarded_delete = guarded_cell_operator(config.delete, "d", function(opts)
    return M.delete(reader_bufnr, opts)
  end)
  if guarded_yank then
    install("y", guarded_yank, "Yank current cell Source with " .. config.yank)
  elseif not has_operator_prefix(config.yank, "y") then
    install(config.yank, function()
      M.yank(reader_bufnr, mapping_options())
    end, "Yank current cell Source")
  end
  if not has_operator_prefix(config.visual, "v") then
    install(config.visual, function()
      M.visual(reader_bufnr, mapping_options())
    end, "Select current rendered cell")
  end
  if guarded_delete then
    install("d", guarded_delete, "Delete current cell Source with " .. config.delete)
  elseif not has_operator_prefix(config.delete, "d") then
    install(config.delete, function()
      M.delete(reader_bufnr, mapping_options())
    end, "Delete current cell Source")
  end
  -- The Source `c` proxy is buffer-local, so Vim can resolve the longer `cic`
  -- alias first. Cell put has no operator-style default, but an explicitly
  -- configured complete alias remains supported.
  install(config.change, function()
    M.change(reader_bufnr, mapping_options())
  end, "Change current cell Source")
  install(config.put, function()
    M.put(reader_bufnr, mapping_options())
  end, "Put register into current cell Source")
  install(config.change_operator, function()
    M.change_or_fallback(reader_bufnr)
  end, "Delegate the native Source change operator")
  install(config.repeat_change, function()
    M.repeat_last(reader_bufnr)
  end, "Repeat the last Source-backed cell change")

  register_operator(config.yank, "y", function(opts)
    return M.yank(reader_bufnr, opts)
  end, "Yank current cell Source")
  register_operator(config.delete, "d", function(opts)
    return M.delete(reader_bufnr, opts)
  end, "Delete current cell Source")
  register_operator(config.change, "c", function(opts)
    return M.change(reader_bufnr, opts)
  end, "Change current cell Source")
  register_operator(config.put, "c", function(opts)
    return M.put(reader_bufnr, opts)
  end, "Put register into current cell Source")

  for suffix, handlers in pairs(operator_text_objects) do
    install(suffix, function()
      local operation = handlers[vim.v.operator]
      if not operation then
        cancel_pending_operator()
        return false
      end
      local opts = mapping_options()
      cancel_pending_operator()
      return operation.callback(opts)
    end, "Markdown table cell text object", "o")
  end

  local visual_suffix
  if type(config.visual) == "string" and config.visual:sub(1, 1) == "v" then
    visual_suffix = config.visual:sub(2)
  end
  if visual_suffix and visual_suffix ~= "" then
    install(visual_suffix, function()
      return M.visual(reader_bufnr, visual_mapping_options())
    end, "Select current rendered cell", "x")
  end
end

function M.cleanup(bufnr)
  M.clear_visual(bufnr)
  clear_pending_change(bufnr)
  last_changes[bufnr] = nil
end

return M
