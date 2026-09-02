local parser = require("markdown-table-wrap.parser")
local render = require("markdown-table-wrap.render")
local mappings = require("markdown-table-wrap.mappings")

local M = {}
local namespace = vim.api.nvim_create_namespace("markdown-table-wrap-reader")
local visual_namespace = vim.api.nvim_create_namespace("markdown-table-wrap-reader-visual")
local states = {}
local source_states = {}
-- Per-Source, per-window Reader viewport written on native leave so auto-reopen
-- can restore cursor/topline after the disposable scratch buffer is deleted.
local saved_views = {}

local function notify_error(action, err)
  vim.notify("MarkdownTableWrap: " .. action .. ": " .. tostring(err), vim.log.levels.ERROR)
end

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function source_name(source_bufnr)
  local name = vim.api.nvim_buf_get_name(source_bufnr)
  if name == "" then
    return "untitled"
  end
  return vim.fn.fnamemodify(name, ":t")
end

local function cell_key(cell)
  if type(cell) ~= "table" or not cell.table_id or cell.row_index == nil or cell.column_index == nil then
    return nil
  end
  return table.concat({ cell.table_id, cell.row_index, cell.column_index }, ":")
end

local function build(source_bufnr, config)
  local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  local tables = parser.parse_all(source_bufnr)
  local output = {}
  local line_objects = {}
  local reader_to_source = {}
  local source_to_reader = {}
  local table_rows = {}
  local segments = {}
  local cell_segments = {}
  local table_headers = {}
  local table_index = 1
  local source_lnum = 1

  local function append(text, mapped_lnum, line_object, is_table)
    table.insert(output, text)
    local reader_lnum = #output
    line_objects[reader_lnum] = line_object or false
    reader_to_source[reader_lnum] = mapped_lnum
    source_to_reader[mapped_lnum] = source_to_reader[mapped_lnum] or reader_lnum
    table_rows[reader_lnum] = is_table == true
    for _, cell in ipairs(type(line_object) == "table" and line_object.cells or {}) do
      local key = cell_key(cell)
      if key then
        cell_segments[key] = cell_segments[key] or {}
        table.insert(cell_segments[key], { row = reader_lnum, cell = cell })
        if line_object.is_header then
          table_headers[cell.table_id] = table_headers[cell.table_id] or {}
          table_headers[cell.table_id][reader_lnum] = line_object.text or ""
        end
      end
    end
  end

  while source_lnum <= #source_lines do
    local table_info = tables[table_index]
    if table_info and table_info.start_lnum == source_lnum then
      local rendered = render.render_table(table_info, config)
      local reader_start = #output + 1

      for index, text in ipairs(rendered.lines) do
        local line_object = rendered.line_objects[index]
        line_object.table_id = table_info.id
        append(text, rendered.source_lnums[index] or table_info.start_lnum, line_object, true)
      end

      table.insert(segments, {
        start_row = reader_start - 1,
        rendered = rendered,
      })
      source_lnum = table_info.end_lnum + 1
      table_index = table_index + 1
    else
      append(source_lines[source_lnum] or "", source_lnum, nil, false)
      source_lnum = source_lnum + 1
    end
  end

  if #output == 0 then
    append("", 1, nil, false)
  end

  return {
    lines = output,
    line_objects = line_objects,
    reader_to_source = reader_to_source,
    source_to_reader = source_to_reader,
    table_rows = table_rows,
    segments = segments,
    cell_segments = cell_segments,
    table_headers = table_headers,
  }
end

local function adjust_viewport_for_cursor(source_bufnr, config, source_lnum, source_col)
  local wide = config and config.wide_table
  if type(wide) ~= "table" or wide.mode ~= "viewport" then
    return config
  end
  local table_info = parser.parse_at_cursor(source_bufnr, source_lnum)
  if not table_info then
    return config
  end
  local row = source_lnum == table_info.start_lnum and table_info.header or nil
  if not row then
    for _, candidate in ipairs(table_info.rows or {}) do
      if candidate.source_lnum == source_lnum then
        row = candidate
        break
      end
    end
  end
  for index, cell in ipairs(row or {}) do
    local span = cell.source_span
    if span and source_col >= span.start_col and source_col <= span.end_col then
      return render.ensure_viewport(config, #table_info.header, index)
    end
  end
  return config
end

local function apply_table_highlights(reader_bufnr, built, config)
  require("markdown-table-wrap.theme").apply(config)
  vim.api.nvim_buf_clear_namespace(reader_bufnr, namespace, 0, -1)
  local overlay_priority = math.max(config.overlay_priority or 10000, 10000)
  for _, segment in ipairs(built.segments) do
    -- Reader keeps the source filetype so prose can still use normal Markdown
    -- rendering. Hide only the already-rendered table text and redraw it as an
    -- authoritative overlay. Otherwise Markdown syntax can pair underscores or
    -- angle brackets across cells, conceal them, and move the visible borders.
    -- One extmark owns both concealment and the fully highlighted overlay; a
    -- second set of range highlights would duplicate work without affecting the
    -- visible Reader line.
    for index, line_obj in ipairs(segment.rendered.line_objects) do
      local row = segment.start_row + index - 1
      local line = line_obj.text or ""
      if line ~= "" then
        vim.api.nvim_buf_set_extmark(reader_bufnr, namespace, row, 0, {
          end_row = row,
          end_col = #line,
          conceal = "",
          virt_text = render.display_chunks(line_obj, index),
          virt_text_pos = "overlay",
          hl_mode = "replace",
          right_gravity = false,
          priority = overlay_priority,
        })
      end
    end
  end
end

local function configure_window(winid, config)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local reader_config = config.reader or {}
  vim.wo[winid].wrap = reader_config.wrap ~= false
  vim.wo[winid].linebreak = reader_config.linebreak == true
  vim.wo[winid].breakindent = reader_config.breakindent ~= false
  vim.wo[winid].conceallevel = math.max(vim.wo[winid].conceallevel, reader_config.conceallevel or 2)
  vim.wo[winid].concealcursor = reader_config.concealcursor or "nvc"
end

local function set_reader_keymaps(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return
  end

  -- Reconfiguration can happen while a logical `vic` session owns temporary
  -- Visual operators. Restore the user's mappings before replacing the
  -- Reader's persistent mapping set.
  require("markdown-table-wrap.cell_ops").clear_visual(reader_bufnr)

  for _, mapping in ipairs(state.installed_mappings or {}) do
    if type(mapping) == "table" then
      pcall(vim.keymap.del, mapping.mode or "n", mapping.lhs, { buffer = reader_bufnr })
    else
      -- Keep compatibility with state snapshots produced before mode-aware
      -- cell text-object mappings were introduced.
      pcall(vim.keymap.del, "n", mapping, { buffer = reader_bufnr })
    end
  end
  state.installed_mappings = {}
  state.passthrough_fallbacks = {}

  local config = (((state.config or {}).mappings or {}).reader or {})
  if config.enabled == false then
    return
  end

  local function map(lhs, callback, desc, modes)
    if type(lhs) ~= "string" or lhs == "" then
      return
    end
    modes = modes or "n"
    vim.keymap.set(modes, lhs, callback, { buffer = reader_bufnr, silent = true, desc = desc })
    if type(modes) == "table" then
      for _, mode in ipairs(modes) do
        table.insert(state.installed_mappings, { mode = mode, lhs = lhs })
      end
    else
      table.insert(state.installed_mappings, { mode = modes, lhs = lhs })
    end
  end

  local function edit(keys, pause)
    require("markdown-table-wrap.reader").edit(reader_bufnr, keys, pause)
  end

  map(config.close, function()
    require("markdown-table-wrap").close_reader()
  end, "Close Markdown table reader")

  map(config.edit, function()
    edit(nil, true)
  end, "Edit Markdown source")

  for _, key in ipairs(config.insert or {}) do
    map(key, function()
      edit(key, false)
    end, "Edit Markdown source")
  end

  map(config.open_link, function()
    local reader = require("markdown-table-wrap.reader")
    if reader.open_link(reader_bufnr, { silent = true }) then
      return
    end

    local state = states[reader_bufnr]
    local position = require("markdown-table-wrap.reader").source_position(reader_bufnr)
    if
      state
      and mappings.invoke(state.gx_fallback, {
        native_gx = true,
        context_bufnr = state.source_bufnr,
        cursor = position and { position[2], position[3] } or nil,
      })
    then
      return
    end

    vim.notify("MarkdownTableWrap: no link target or gx fallback is available.", vim.log.levels.INFO)
  end, "Open rendered Markdown table link")

  map(config.help, function()
    require("markdown-table-wrap.actions").run("help", { bufnr = reader_bufnr })
  end, "Show Markdown table reader help")

  map(config.copy_cell, function()
    require("markdown-table-wrap.export").cell({ bufnr = reader_bufnr })
  end, "Copy rendered Markdown table cell")

  map(config.copy_table, function()
    require("markdown-table-wrap.export").table({ bufnr = reader_bufnr })
  end, "Copy rendered Markdown table")

  require("markdown-table-wrap.cell_ops").install(function(lhs, callback, description, modes)
    map(lhs, callback, description, modes)
  end, reader_bufnr, state)

  for lhs, spec in pairs(config.passthrough or {}) do
    local passthrough_lhs = lhs
    local passthrough_spec = spec
    state.passthrough_fallbacks[passthrough_lhs] = mappings.get(state.source_bufnr, passthrough_lhs, "n")
    map(passthrough_lhs, function()
      require("markdown-table-wrap.actions").passthrough(reader_bufnr, passthrough_lhs, passthrough_spec)
    end, "Markdown table reader passthrough")
  end
end

local function acquire_source(source_bufnr, reader_bufnr)
  local source_state = source_states[source_bufnr]
  if not source_state then
    source_state = {
      original_bufhidden = vim.bo[source_bufnr].bufhidden,
      readers = {},
    }
    source_states[source_bufnr] = source_state
  end

  source_state.readers[reader_bufnr] = true
  vim.bo[source_bufnr].bufhidden = "hide"
  return source_state.original_bufhidden
end

local function release_source(state, reader_bufnr)
  local source_bufnr = state and state.source_bufnr
  local source_state = source_bufnr and source_states[source_bufnr] or nil
  if not source_state then
    return
  end

  source_state.readers[reader_bufnr] = nil
  if next(source_state.readers) ~= nil then
    return
  end

  if vim.api.nvim_buf_is_valid(source_bufnr) then
    vim.bo[source_bufnr].bufhidden = source_state.original_bufhidden or ""
  end
  source_states[source_bufnr] = nil
end

local function restore_window(state)
  local winid = state and state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  for option, value in pairs(state.source_options or {}) do
    vim.wo[winid][option] = value
  end
end

local function create_reader_buffer(source_bufnr)
  local reader_bufnr = vim.api.nvim_create_buf(false, true)
  local configured, configure_error = pcall(function()
    vim.b[reader_bufnr].markdown_table_wrap_reader = true
    vim.b[reader_bufnr].markdown_table_wrap_source = source_bufnr
    -- acwrite lets :write save the backing Markdown buffer while
    -- modifiable=false continues to protect the rendered view from direct
    -- edits.
    vim.bo[reader_bufnr].buftype = "acwrite"
    vim.bo[reader_bufnr].bufhidden = "hide"
    vim.bo[reader_bufnr].swapfile = false
    vim.bo[reader_bufnr].undofile = false
    vim.bo[reader_bufnr].modifiable = true

    pcall(
      vim.api.nvim_buf_set_name,
      reader_bufnr,
      string.format("markdown-table-wrap://reader/%d/%s", reader_bufnr, source_name(source_bufnr))
    )

    vim.bo[reader_bufnr].filetype = vim.bo[source_bufnr].filetype
    vim.api.nvim_create_autocmd("BufWinLeave", {
      buffer = reader_bufnr,
      callback = function()
        require("markdown-table-wrap.reader").sync_view(reader_bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufHidden", {
      buffer = reader_bufnr,
      once = true,
      callback = function()
        require("markdown-table-wrap.reader").abandon(reader_bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = reader_bufnr,
      once = true,
      callback = function()
        require("markdown-table-wrap.reader").cleanup(reader_bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = reader_bufnr,
      callback = function()
        local ok, err = require("markdown-table-wrap.reader").write(reader_bufnr)
        if not ok then
          error("MarkdownTableWrap: could not save source Markdown: " .. tostring(err))
        end
      end,
    })
  end)
  if not configured then
    if vim.api.nvim_buf_is_valid(reader_bufnr) then
      pcall(vim.api.nvim_buf_delete, reader_bufnr, { force = true })
    end
    error(configure_error)
  end
  return reader_bufnr
end

local function source_cursor_for(state, reader_lnum, reader_col)
  local source_lnum = state.reader_to_source[reader_lnum] or 1
  local source_line = vim.api.nvim_buf_get_lines(state.source_bufnr, source_lnum - 1, source_lnum, false)[1] or ""
  local source_col = math.min(reader_col, #source_line)
  if state.table_rows[reader_lnum] then
    source_col = 0
    local line_object = state.line_objects[reader_lnum]
    for _, cell in ipairs(type(line_object) == "table" and line_object.cells or {}) do
      if reader_col >= cell.start_col and reader_col < cell.end_col then
        local span = cell.source_span or require("markdown-table-wrap.nav").spans(source_line)[cell.index]
        source_col = span and span.start_col or 0
        break
      end
    end
  end
  return source_lnum, source_col
end

local function clamp_lnum(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 1
  end
  return math.max(1, math.min(tonumber(lnum) or 1, vim.api.nvim_buf_line_count(bufnr)))
end

local function wrap_offset(mapping, reader_lnum, source_lnum)
  local first = mapping and mapping[source_lnum]
  if not first then
    return 0
  end
  return math.max(0, (tonumber(reader_lnum) or 1) - first)
end

local function last_reader_line_for_source(built, source_lnum)
  local first = built.source_to_reader[source_lnum]
  if not first then
    return nil
  end
  local last = first
  for reader_lnum = first + 1, #(built.lines or {}) do
    if built.reader_to_source[reader_lnum] ~= source_lnum then
      break
    end
    last = reader_lnum
  end
  return last
end

local function map_source_line(built, source_lnum, offset)
  local last_line = math.max(1, #(built.lines or {}))
  local first = built.source_to_reader[source_lnum]
  if not first then
    return math.max(1, math.min(tonumber(source_lnum) or 1, last_line))
  end
  local last = last_reader_line_for_source(built, source_lnum) or first
  return math.max(1, math.min(first + (tonumber(offset) or 0), last, last_line))
end

local function view_extras(view)
  if type(view) ~= "table" then
    return { leftcol = 0, coladd = 0 }
  end
  local extras = {
    leftcol = tonumber(view.leftcol) or 0,
    coladd = tonumber(view.coladd) or 0,
  }
  if view.curswant ~= nil then
    extras.curswant = view.curswant
  end
  if view.skipcol ~= nil then
    extras.skipcol = view.skipcol
  end
  if view.topfill ~= nil then
    extras.topfill = view.topfill
  end
  return extras
end

local function with_view_extras(base, view)
  for key, value in pairs(view_extras(view)) do
    if base[key] == nil then
      base[key] = value
    end
  end
  return base
end

local function snapshot_changedtick_matches(saved, source_bufnr)
  if not saved or not saved.source_changedtick or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return false
  end
  return saved.source_changedtick == vim.api.nvim_buf_get_changedtick(source_bufnr)
end

local function source_view_matches_snapshot(source_view, saved)
  return saved and tonumber(source_view.lnum) == tonumber(saved.source_lnum)
end

local function reader_winid(state, reader_bufnr)
  local winid = state and state.winid
  if winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == reader_bufnr then
    return winid
  end
  return vim.fn.win_findbuf(reader_bufnr)[1]
end

local function get_saved_view(source_bufnr, winid)
  local by_win = saved_views[source_bufnr]
  return by_win and by_win[winid] or nil
end

local function store_saved_view(source_bufnr, winid, view)
  if not source_bufnr or not winid or not view then
    return
  end
  saved_views[source_bufnr] = saved_views[source_bufnr] or {}
  saved_views[source_bufnr][winid] = view
end

local function clear_saved_view(source_bufnr, winid)
  if not source_bufnr then
    return
  end
  if not winid then
    saved_views[source_bufnr] = nil
    return
  end
  local by_win = saved_views[source_bufnr]
  if not by_win then
    return
  end
  by_win[winid] = nil
  if next(by_win) == nil then
    saved_views[source_bufnr] = nil
  end
end

local function source_winrestview(view, source_bufnr)
  local lnum = clamp_lnum(source_bufnr, view.source_lnum or view.lnum)
  local topline = clamp_lnum(source_bufnr, view.source_topline or view.topline or lnum)
  if topline > lnum then
    topline = lnum
  end
  local line = vim.api.nvim_buf_get_lines(source_bufnr, lnum - 1, lnum, false)[1] or ""
  local col = math.max(0, math.min(tonumber(view.source_col or view.col) or 0, #line))
  return with_view_extras({
    lnum = lnum,
    col = col,
    topline = topline,
  }, view)
end

local function capture_view(reader_bufnr, winid)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return nil
  end
  winid = winid or reader_winid(state, reader_bufnr)
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    return nil
  end

  local ok, view = pcall(vim.api.nvim_win_call, winid, function()
    return vim.fn.winsaveview()
  end)
  if not ok or type(view) ~= "table" then
    return nil
  end

  local source_lnum, source_col = source_cursor_for(state, view.lnum, view.col)
  local source_topline = state.reader_to_source[view.topline] or source_lnum
  local captured = with_view_extras({
    source_lnum = source_lnum,
    source_col = source_col,
    source_topline = source_topline,
    cursor_offset = wrap_offset(state.source_to_reader, view.lnum, source_lnum),
    topline_offset = wrap_offset(state.source_to_reader, view.topline, source_topline),
    source_changedtick = vim.api.nvim_buf_get_changedtick(state.source_bufnr),
    winid = winid,
    applied = false,
  }, view)
  return captured
end

local function apply_source_view(source_bufnr, winid, view)
  if not view or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return false
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  if vim.api.nvim_win_get_buf(winid) ~= source_bufnr then
    return false
  end
  local restored = source_winrestview(view, source_bufnr)
  return pcall(vim.api.nvim_win_call, winid, function()
    vim.fn.winrestview(restored)
  end)
end

local function restore_reader_view(winid, built, source_view)
  if not winid or not vim.api.nvim_win_is_valid(winid) or type(built) ~= "table" or type(source_view) ~= "table" then
    return
  end

  local cursor_offset = source_view.cursor_offset
  local topline_offset = source_view.topline_offset
  if not built.source_to_reader[source_view.lnum] then
    cursor_offset = 0
  end
  if not built.source_to_reader[source_view.topline] then
    topline_offset = 0
  end

  local reader_lnum = map_source_line(built, source_view.lnum, cursor_offset)
  local reader_topline = map_source_line(built, source_view.topline, topline_offset)
  if reader_lnum < reader_topline then
    reader_topline = reader_lnum
  end
  local line = built.lines[reader_lnum] or ""
  local col = math.max(0, math.min(tonumber(source_view.col) or 0, #line))
  pcall(vim.api.nvim_win_call, winid, function()
    vim.fn.winrestview(with_view_extras({
      lnum = reader_lnum,
      col = col,
      topline = reader_topline,
    }, source_view))
  end)
end

function M.clear_saved_views(bufnr, winid)
  bufnr = tonumber(bufnr)
  winid = tonumber(winid)
  if bufnr then
    clear_saved_view(bufnr, winid)
    return
  end
  if not winid then
    saved_views = {}
    return
  end
  for source_bufnr, by_win in pairs(saved_views) do
    by_win[winid] = nil
    if next(by_win) == nil then
      saved_views[source_bufnr] = nil
    end
  end
end

function M.sync_view(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or state.closing then
    return false
  end

  local winid = vim.api.nvim_get_current_win()
  local view = capture_view(reader_bufnr, winid) or capture_view(reader_bufnr, state.winid)
  if not view then
    return false
  end

  local target_win = view.winid or winid or state.winid
  store_saved_view(state.source_bufnr, target_win, view)
  return true
end

function M.restore_source_view(source_bufnr, winid)
  source_bufnr = normalize_bufnr(source_bufnr)
  winid = winid or vim.api.nvim_get_current_win()
  local saved = get_saved_view(source_bufnr, winid)
  if not saved or saved.applied then
    return false
  end
  if not snapshot_changedtick_matches(saved, source_bufnr) then
    clear_saved_view(source_bufnr, winid)
    return false
  end
  if not saved.enter_recorded and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == source_bufnr then
    local ok, live = pcall(vim.api.nvim_win_call, winid, function()
      return vim.fn.winsaveview()
    end)
    if ok and type(live) == "table" then
      saved.enter_lnum = live.lnum
      saved.enter_recorded = true
    end
  end
  if not apply_source_view(source_bufnr, winid, saved) then
    return false
  end
  saved.applied = true
  return true
end

function M.invalidate_source_view(source_bufnr, winid)
  source_bufnr = normalize_bufnr(source_bufnr)
  winid = tonumber(winid)
  local by_win = saved_views[source_bufnr]
  if not by_win then
    return false
  end

  local tick = vim.api.nvim_buf_is_valid(source_bufnr) and vim.api.nvim_buf_get_changedtick(source_bufnr) or nil
  local function stale(saved)
    return not saved.source_changedtick or not tick or saved.source_changedtick ~= tick
  end

  if not winid then
    local cleared = false
    for saved_win, saved in pairs(by_win) do
      if stale(saved) then
        by_win[saved_win] = nil
        cleared = true
      end
    end
    if next(by_win) == nil then
      saved_views[source_bufnr] = nil
    end
    return cleared
  end

  local saved = by_win[winid]
  if not saved then
    return false
  end
  if stale(saved) then
    clear_saved_view(source_bufnr, winid)
    return true
  end
  if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= source_bufnr then
    return false
  end
  local ok, view = pcall(vim.api.nvim_win_call, winid, function()
    return vim.fn.winsaveview()
  end)
  if not ok or type(view) ~= "table" then
    return false
  end
  if saved.applied then
    if view.lnum ~= saved.source_lnum then
      clear_saved_view(source_bufnr, winid)
      return true
    end
    return false
  end
  if saved.enter_recorded and view.lnum ~= saved.enter_lnum then
    clear_saved_view(source_bufnr, winid)
    return true
  end
  return false
end

function M.is_reader(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return states[bufnr] ~= nil or vim.b[bufnr].markdown_table_wrap_reader == true
end

function M.source_bufnr(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  if not vim.api.nvim_buf_is_valid(reader_bufnr) then
    return nil
  end
  local state = states[reader_bufnr]
  return state and state.source_bufnr or vim.b[reader_bufnr].markdown_table_wrap_source
end

function M.source_changedtick(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return nil
  end
  return state.source_changedtick
end

function M.open(source_bufnr, config, opts)
  opts = opts or {}
  source_bufnr = normalize_bufnr(source_bufnr)
  if not vim.api.nvim_buf_is_valid(source_bufnr) or M.is_reader(source_bufnr) then
    return nil
  end

  local winid = vim.api.nvim_get_current_win()
  local saved = nil
  if opts.auto then
    saved = get_saved_view(source_bufnr, winid)
    if saved and not snapshot_changedtick_matches(saved, source_bufnr) then
      clear_saved_view(source_bufnr, winid)
      saved = nil
    elseif saved and not saved.applied then
      local live = vim.api.nvim_win_call(winid, function()
        return vim.fn.winsaveview()
      end)
      if saved.enter_recorded and live.lnum ~= saved.enter_lnum then
        clear_saved_view(source_bufnr, winid)
        saved = nil
      elseif apply_source_view(source_bufnr, winid, saved) then
        saved.applied = true
      end
    end
  else
    clear_saved_view(source_bufnr, winid)
  end

  local source_view = vim.api.nvim_win_call(winid, function()
    return vim.fn.winsaveview()
  end)
  if
    opts.auto
    and saved
    and snapshot_changedtick_matches(saved, source_bufnr)
    and source_view_matches_snapshot(source_view, saved)
  then
    source_view.cursor_offset = saved.cursor_offset
    source_view.topline_offset = saved.topline_offset
  end
  local source_cursor = { source_view.lnum, source_view.col }
  local source_alt_bufnr = vim.fn.bufnr("#")
  local source_options = {
    wrap = vim.wo[winid].wrap,
    linebreak = vim.wo[winid].linebreak,
    breakindent = vim.wo[winid].breakindent,
    conceallevel = vim.wo[winid].conceallevel,
    concealcursor = vim.wo[winid].concealcursor,
    winbar = vim.wo[winid].winbar,
  }
  local built_ok, adjusted_or_error, built = pcall(function()
    local adjusted = adjust_viewport_for_cursor(source_bufnr, config, source_cursor[1], source_cursor[2])
    return adjusted, build(source_bufnr, adjusted)
  end)
  if not built_ok then
    notify_error("could not build Reader", adjusted_or_error)
    return nil
  end
  config = adjusted_or_error

  local reader_bufnr
  local ownership = { source_bufnr = source_bufnr }
  local prepared, prepare_error = pcall(function()
    reader_bufnr = create_reader_buffer(source_bufnr)
    ownership.source_bufhidden = acquire_source(source_bufnr, reader_bufnr)
    vim.api.nvim_buf_set_lines(reader_bufnr, 0, -1, false, built.lines)
    apply_table_highlights(reader_bufnr, built, config)
    vim.bo[reader_bufnr].modifiable = false
    vim.bo[reader_bufnr].readonly = false
    vim.bo[reader_bufnr].modified = vim.bo[source_bufnr].modified

    states[reader_bufnr] = vim.tbl_extend("force", built, {
      source_bufnr = source_bufnr,
      source_changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr),
      config = config,
      winid = winid,
      source_options = source_options,
      source_bufhidden = ownership.source_bufhidden,
      source_alt_bufnr = source_alt_bufnr > 0 and source_alt_bufnr or nil,
      gx_fallback = mappings.get(source_bufnr, "gx", "n"),
    })
    set_reader_keymaps(reader_bufnr)
  end)
  if not prepared then
    if reader_bufnr then
      states[reader_bufnr] = nil
      release_source(ownership, reader_bufnr)
      if vim.api.nvim_buf_is_valid(reader_bufnr) then
        pcall(vim.api.nvim_buf_delete, reader_bufnr, { force = true })
      end
    end
    notify_error("could not prepare Reader", prepare_error)
    return nil
  end

  local switched, switch_err = pcall(vim.api.nvim_win_set_buf, winid, reader_bufnr)
  if not switched then
    release_source(states[reader_bufnr], reader_bufnr)
    states[reader_bufnr] = nil
    pcall(vim.api.nvim_buf_delete, reader_bufnr, { force = true })
    notify_error("could not open Reader", switch_err)
    return nil
  end
  local finalized, finalize_error = pcall(function()
    configure_window(winid, config)
    restore_reader_view(winid, built, source_view)
    M.update_sticky_header(reader_bufnr, winid)
  end)
  if not finalized then
    local state = states[reader_bufnr]
    if
      vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_win_get_buf(winid) == reader_bufnr
      and vim.api.nvim_buf_is_valid(source_bufnr)
    then
      pcall(vim.api.nvim_win_set_buf, winid, source_bufnr)
    end
    restore_window(state)
    states[reader_bufnr] = nil
    release_source(state or ownership, reader_bufnr)
    if vim.api.nvim_buf_is_valid(reader_bufnr) then
      pcall(vim.api.nvim_buf_delete, reader_bufnr, { force = true })
    end
    notify_error("could not finalize Reader", finalize_error)
    return nil
  end
  local event_data = {
    mode = "reader",
    source_bufnr = source_bufnr,
    view_bufnr = reader_bufnr,
    winid = winid,
  }
  require("markdown-table-wrap.events").emit("MarkdownTableWrapReaderEnter", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", event_data)
  return reader_bufnr
end

function M.close(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return nil
  end

  local winid = state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    winid = vim.fn.win_findbuf(reader_bufnr)[1]
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    M.abandon(reader_bufnr)
    return state.source_bufnr
  end

  local view = capture_view(reader_bufnr, winid)
  local fallback_lnum, fallback_col
  if not view then
    local reader_cursor = vim.api.nvim_win_get_cursor(winid)
    fallback_lnum, fallback_col = source_cursor_for(state, reader_cursor[1], reader_cursor[2])
  end
  -- The Reader mirrors source's modified flag so :x and ZZ save correctly.
  -- Clear only the disposable mirror before switching away from this view.
  vim.bo[reader_bufnr].modified = false
  state.closing = true
  M.clear_visual_selection(reader_bufnr)
  local switched, switch_err = pcall(vim.api.nvim_win_set_buf, winid, state.source_bufnr)
  if not switched then
    state.closing = false
    vim.bo[reader_bufnr].modified = vim.bo[state.source_bufnr].modified
    vim.notify("MarkdownTableWrap: could not restore source: " .. tostring(switch_err), vim.log.levels.ERROR)
    return nil
  end

  restore_window(state)
  if view then
    if not apply_source_view(state.source_bufnr, winid, view) then
      pcall(vim.api.nvim_win_set_cursor, winid, { view.source_lnum, view.source_col })
    end
  elseif fallback_lnum then
    pcall(vim.api.nvim_win_set_cursor, winid, { fallback_lnum, fallback_col })
  end
  clear_saved_view(state.source_bufnr, winid)

  states[reader_bufnr] = nil
  release_source(state, reader_bufnr)
  local event_data = {
    mode = "source",
    source_bufnr = state.source_bufnr,
    view_bufnr = state.source_bufnr,
    previous_view_bufnr = reader_bufnr,
    winid = winid,
  }
  require("markdown-table-wrap.events").emit("MarkdownTableWrapReaderLeave", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)
  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.api.nvim_buf_delete(reader_bufnr, { force = true })
  end
  return state.source_bufnr
end

function M.edit(reader_bufnr, keys, pause)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local source_bufnr = M.close(reader_bufnr)
  if not source_bufnr then
    return false
  end

  if pause then
    require("markdown-table-wrap").pause_buffer(source_bufnr)
  end

  if keys and keys ~= "" then
    local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.schedule(function()
      vim.api.nvim_feedkeys(encoded, "n", false)
    end)
  end
  return true
end

function M.write(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return false, "the backing source buffer is no longer available"
  end

  if vim.api.nvim_buf_get_name(state.source_bufnr) == "" then
    return false, "the source buffer has no file name; use :w {path} after entering source mode"
  end

  local ok, err = pcall(vim.api.nvim_buf_call, state.source_bufnr, function()
    vim.cmd("write")
  end)
  if not ok then
    return false, err
  end

  if vim.api.nvim_buf_is_valid(reader_bufnr) and states[reader_bufnr] then
    M.refresh(reader_bufnr)
  end
  return true
end

function M.refresh(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return false
  end

  local winid = state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    winid = vim.fn.win_findbuf(reader_bufnr)[1]
    state.winid = winid
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  M.clear_visual_selection(reader_bufnr)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local source_lnum = state.reader_to_source[cursor[1]] or 1
  local source_col = select(2, source_cursor_for(state, cursor[1], cursor[2]))
  local built_ok, next_config_or_error, built = pcall(function()
    local candidate_config = vim.deepcopy(state.config)
    local next_config = adjust_viewport_for_cursor(state.source_bufnr, candidate_config, source_lnum, source_col)
    return next_config,
      vim.api.nvim_win_call(winid, function()
        return build(state.source_bufnr, next_config)
      end)
  end)
  if not built_ok then
    notify_error("could not rebuild Reader", next_config_or_error)
    return false
  end
  local next_config = next_config_or_error

  local applied, apply_error = pcall(function()
    vim.bo[reader_bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(reader_bufnr, 0, -1, false, built.lines)
    apply_table_highlights(reader_bufnr, built, next_config)
  end)
  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.bo[reader_bufnr].modifiable = false
    vim.bo[reader_bufnr].readonly = false
    if vim.api.nvim_buf_is_valid(state.source_bufnr) then
      vim.bo[reader_bufnr].modified = vim.bo[state.source_bufnr].modified
    end
  end
  if not applied or states[reader_bufnr] ~= state then
    if vim.api.nvim_buf_is_valid(reader_bufnr) and states[reader_bufnr] == state then
      pcall(function()
        vim.bo[reader_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(reader_bufnr, 0, -1, false, state.lines or { "" })
        apply_table_highlights(reader_bufnr, state, state.config)
      end)
      if vim.api.nvim_buf_is_valid(reader_bufnr) then
        vim.bo[reader_bufnr].modifiable = false
        vim.bo[reader_bufnr].readonly = false
        if vim.api.nvim_buf_is_valid(state.source_bufnr) then
          vim.bo[reader_bufnr].modified = vim.bo[state.source_bufnr].modified
        end
      end
    end
    notify_error("could not update Reader projection", apply_error or "Reader state changed during refresh")
    return false
  end

  for key, value in pairs(built) do
    state[key] = value
  end
  state.config = next_config
  state.source_changedtick = vim.api.nvim_buf_get_changedtick(state.source_bufnr)

  local finalized, finalize_error = pcall(function()
    configure_window(winid, state.config)
    local reader_lnum = state.source_to_reader[source_lnum] or 1
    local line = state.lines[reader_lnum] or ""
    vim.api.nvim_win_set_cursor(winid, { reader_lnum, math.min(cursor[2], #line) })
    M.update_sticky_header(reader_bufnr, winid)
  end)
  if not finalized then
    notify_error("could not finalize Reader refresh", finalize_error)
    return false
  end
  require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", {
    mode = "reader",
    source_bufnr = state.source_bufnr,
    view_bufnr = reader_bufnr,
    winid = winid,
  })
  return true
end

function M.reconfigure(reader_bufnr, config)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return false
  end

  state.config = config
  state.gx_fallback = mappings.get(state.source_bufnr, "gx", "n")
  set_reader_keymaps(reader_bufnr)
  if #vim.fn.win_findbuf(reader_bufnr) == 0 then
    return true
  end
  return M.refresh(reader_bufnr)
end

function M.has_source_readers(source_bufnr)
  source_bufnr = normalize_bufnr(source_bufnr)
  local source_state = source_states[source_bufnr]
  return source_state ~= nil and next(source_state.readers) ~= nil
end

function M.refresh_source(source_bufnr)
  source_bufnr = normalize_bufnr(source_bufnr)
  local source_state = source_states[source_bufnr]
  if not source_state then
    return 0
  end

  local refreshed = 0
  local changedtick = vim.api.nvim_buf_is_valid(source_bufnr) and vim.api.nvim_buf_get_changedtick(source_bufnr) or nil
  for reader_bufnr in pairs(source_state.readers) do
    if
      states[reader_bufnr]
      and changedtick
      and states[reader_bufnr].source_changedtick ~= changedtick
      and M.refresh(reader_bufnr)
    then
      refreshed = refreshed + 1
    end
  end
  return refreshed
end

function M.refresh_windows(winids)
  local selected
  if type(winids) == "table" then
    selected = {}
    for _, winid in ipairs(winids) do
      winid = tonumber(winid)
      if winid then
        selected[winid] = true
      end
    end
  end

  local targets = {}
  for reader_bufnr, state in pairs(states) do
    local winid = state.winid
    if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
      winid = vim.fn.win_findbuf(reader_bufnr)[1]
      state.winid = winid
    end
    if winid and vim.api.nvim_win_is_valid(winid) and (not selected or selected[winid]) then
      table.insert(targets, reader_bufnr)
    end
  end
  table.sort(targets)

  local refreshed = 0
  for _, reader_bufnr in ipairs(targets) do
    if M.refresh(reader_bufnr) then
      refreshed = refreshed + 1
    end
  end
  return refreshed
end

function M.open_link(reader_bufnr, opts)
  opts = opts or {}
  reader_bufnr = normalize_bufnr(reader_bufnr)
  if not states[reader_bufnr] then
    return false
  end
  local context = require("markdown-table-wrap.context").resolve({ bufnr = reader_bufnr })
  return context and require("markdown-table-wrap.links").open_at_context(context, opts) or false
end

function M.abandon(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or state.closing then
    return false
  end

  M.sync_view(reader_bufnr)

  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    M.clear_visual_selection(reader_bufnr)
    vim.bo[reader_bufnr].modified = false
    vim.b[reader_bufnr].markdown_table_wrap_reader = nil
    vim.b[reader_bufnr].markdown_table_wrap_source = nil
  end
  restore_window(state)
  states[reader_bufnr] = nil
  release_source(state, reader_bufnr)
  local event_data = {
    mode = "source",
    source_bufnr = state.source_bufnr,
    view_bufnr = state.source_bufnr,
    previous_view_bufnr = reader_bufnr,
    winid = state.winid,
    implicit = true,
  }
  require("markdown-table-wrap.events").emit("MarkdownTableWrapReaderLeave", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)

  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(reader_bufnr) then
        pcall(vim.api.nvim_buf_delete, reader_bufnr, { force = true })
      end
    end)
  end
  return true
end

function M.cleanup(bufnr)
  clear_saved_view(bufnr)
  local state = states[bufnr]
  if state then
    M.clear_visual_selection(bufnr)
    restore_window(state)
    states[bufnr] = nil
    release_source(state, bufnr)
    return
  end

  local source_state = source_states[bufnr]
  if source_state then
    local readers = vim.tbl_keys(source_state.readers)
    source_states[bufnr] = nil
    for _, dependent in ipairs(readers) do
      local dependent_bufnr = dependent
      local dependent_state = states[dependent_bufnr]
      M.clear_visual_selection(dependent_bufnr)
      restore_window(dependent_state)
      states[dependent_bufnr] = nil
      if vim.api.nvim_buf_is_valid(dependent_bufnr) then
        vim.bo[dependent_bufnr].modified = false
        vim.b[dependent_bufnr].markdown_table_wrap_reader = nil
        vim.b[dependent_bufnr].markdown_table_wrap_source = nil
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(dependent_bufnr) then
            pcall(vim.api.nvim_buf_delete, dependent_bufnr, { force = true })
          end
        end)
      end
    end
  end
end

function M.get_state(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  return state and vim.deepcopy(state) or nil
end

-- Internal consumers should prefer these narrow snapshots over get_state().
-- The full state contains every rendered line and semantic object, so copying
-- it for a cursor-local action makes that action scale with the whole Reader.
function M.summary(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return nil
  end
  return {
    rendered_lines = #(state.lines or {}),
    source_alt_bufnr = state.source_alt_bufnr,
  }
end

function M.line_object(reader_bufnr, row)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  row = tonumber(row)
  local line_object = state and row and state.line_objects and state.line_objects[row] or nil
  return type(line_object) == "table" and vim.deepcopy(line_object) or nil
end

function M.cell_segments(reader_bufnr, cell)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  local key = cell_key(cell)
  local segments = state and key and state.cell_segments and state.cell_segments[key] or nil
  return segments and vim.deepcopy(segments) or nil
end

function M.rendered_table(reader_bufnr, table_id)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not table_id then
    return nil
  end
  for _, segment in ipairs(state.segments or {}) do
    if segment.rendered and segment.rendered.table_id == table_id then
      return vim.deepcopy(segment.rendered)
    end
  end
  return nil
end

function M.mapping_fallback(reader_bufnr, group, lhs)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return nil
  end
  local fallbacks = group == "cell" and state.cell_fallbacks
    or group == "passthrough" and state.passthrough_fallbacks
    or nil
  local mapping = fallbacks and fallbacks[lhs] or nil
  return mapping and vim.deepcopy(mapping) or nil
end

function M.source_position(reader_bufnr, winid)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return nil
  end

  winid = winid or state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return { state.source_bufnr, 1, 0 }
  end
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local lnum, col = source_cursor_for(state, cursor[1], cursor[2])
  return { state.source_bufnr, lnum, col }
end

local function same_cell(left, right)
  return left
    and right
    and left.table_id == right.table_id
    and left.row_index == right.row_index
    and left.column_index == right.column_index
end

function M.cell_at_cursor(reader_bufnr, winid)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return nil
  end

  winid = winid or state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    winid = vim.fn.win_findbuf(reader_bufnr)[1]
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local line_object = state.line_objects[cursor[1]]
  if type(line_object) ~= "table" then
    return nil
  end

  local current
  for _, cell in ipairs(line_object.cells or {}) do
    if cursor[2] >= cell.start_col and cursor[2] < cell.end_col then
      current = cell
      break
    end
  end
  if not current then
    return nil
  end

  local key = cell_key(current)
  local indexed = key and state.cell_segments and state.cell_segments[key] or nil
  local start_row
  local end_row
  local start_col = current.start_col
  local end_col = current.end_col
  if indexed then
    for _, item in ipairs(indexed) do
      local row = item.row
      local cell = item.cell
      start_row = start_row and math.min(start_row, row) or row
      end_row = end_row and math.max(end_row, row) or row
      start_col = math.min(start_col, cell.start_col)
      end_col = math.max(end_col, cell.end_col)
    end
  else
    for row, object in ipairs(state.line_objects) do
      if type(object) == "table" then
        for _, cell in ipairs(object.cells or {}) do
          if same_cell(cell, current) then
            start_row = start_row and math.min(start_row, row) or row
            end_row = end_row and math.max(end_row, row) or row
            start_col = math.min(start_col, cell.start_col)
            end_col = math.max(end_col, cell.end_col)
          end
        end
      end
    end
  end

  return {
    source_bufnr = state.source_bufnr,
    winid = winid,
    table_id = current.table_id,
    row_index = current.row_index,
    column_index = current.column_index,
    source_span = vim.deepcopy(current.source_span),
    present = current.present ~= false,
    text = current.text,
    render_start_row = start_row or cursor[1],
    render_end_row = end_row or cursor[1],
    render_start_col = start_col,
    render_end_col = end_col,
  }
end

function M.focus_source_cell(reader_bufnr, source_lnum, column_index, table_id, row_index)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return false
  end
  local winid = state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    winid = vim.fn.win_findbuf(reader_bufnr)[1]
  end
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local key = cell_key({
    table_id = table_id,
    row_index = row_index,
    column_index = column_index,
  })
  local indexed = key and state.cell_segments and state.cell_segments[key] or nil
  local first = indexed and indexed[1] or nil
  if first then
    vim.api.nvim_win_set_cursor(winid, { first.row, first.cell.start_col })
    return true
  end

  for row, object in ipairs(state.line_objects) do
    if type(object) == "table" then
      for _, cell in ipairs(object.cells or {}) do
        local span = cell.source_span
        if
          span
          and span.start_lnum == source_lnum
          and cell.column_index == column_index
          and (not table_id or cell.table_id == table_id)
        then
          vim.api.nvim_win_set_cursor(winid, { row, cell.start_col })
          return true
        end
      end
    end
  end
  return false
end

function M.clear_visual_selection(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  if vim.api.nvim_buf_is_valid(reader_bufnr) then
    vim.api.nvim_buf_clear_namespace(reader_bufnr, visual_namespace, 0, -1)
  end
end

function M.update_sticky_header(reader_bufnr, winid)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return false
  end
  winid = winid or state.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    return false
  end
  if not (state.config.reader or {}).sticky_header then
    vim.wo[winid].winbar = state.source_options and state.source_options.winbar or ""
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local line_object = state.line_objects[cursor[1]]
  local table_id = type(line_object) == "table" and line_object.table_id or nil
  if not table_id then
    for _, segment in ipairs(state.segments or {}) do
      if cursor[1] >= segment.start_row + 1 and cursor[1] <= segment.start_row + segment.rendered.height then
        table_id = segment.rendered.table_id
        break
      end
    end
  end
  local headers = table_id and state.table_headers and state.table_headers[table_id] or nil
  if not headers then
    vim.wo[winid].winbar = state.source_options and state.source_options.winbar or ""
    return false
  end
  local values = {}
  local header_rows = vim.tbl_keys(headers)
  table.sort(header_rows)
  for _, row in ipairs(header_rows) do
    table.insert(values, headers[row])
  end
  local text = table.concat(values, " / "):gsub("%%", "%%%%")
  vim.wo[winid].winbar = text ~= "" and (" " .. text) or ""
  return text ~= ""
end

local function visual_bounds(reader_bufnr, winid)
  local mode = vim.api.nvim_get_mode().mode
  if not mode:match("^[vV\22]") then
    return nil
  end

  local state = states[reader_bufnr]
  if not state then
    return nil
  end
  local anchor = vim.fn.getpos("v")
  if type(anchor) ~= "table" then
    return nil
  end
  -- getpos() returns {bufnum, lnum, col, off}; unlike nvim_win_get_cursor(),
  -- its line and column fields are 1-based.  A zero buffer number means the
  -- current buffer, so only reject an explicit anchor from another buffer.
  if anchor[1] and anchor[1] ~= 0 and anchor[1] ~= reader_bufnr then
    return nil
  end
  local anchor_lnum = anchor[2]
  local anchor_col = math.max((anchor[3] or 1) - 1, 0)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local first_lnum = math.min(anchor_lnum, cursor[1])
  local last_lnum = math.max(anchor_lnum, cursor[1])
  local first_col
  local last_col
  if mode == "V" then
    first_col = 0
    last_col = math.huge
  elseif anchor_lnum < cursor[1] then
    first_col = anchor_col
    last_col = cursor[2]
  elseif cursor[1] < anchor_lnum then
    first_col = cursor[2]
    last_col = anchor_col
  else
    first_col = math.min(anchor_col, cursor[2])
    last_col = math.max(anchor_col, cursor[2])
  end
  return mode, first_lnum, last_lnum, first_col, last_col
end

local function update_logical_cell_visual(reader_bufnr, state)
  local marker = vim.b[reader_bufnr].markdown_table_wrap_cell_visual
  if type(marker) ~= "table" then
    return false
  end

  local key = table.concat({ marker.table_id, marker.row_index, marker.column_index }, ":")
  local segments = state.cell_segments and state.cell_segments[key] or nil
  if not segments or #segments == 0 then
    return false
  end

  local priority = math.max((state.config.overlay_priority or 10000) + 1, 10001)
  for _, item in ipairs(segments) do
    local row = item.row
    local cell = item.cell
    local line = vim.api.nvim_buf_get_lines(reader_bufnr, row - 1, row, false)[1] or ""
    local start_col = math.max(0, math.min(#line, cell.start_col or 0))
    local end_col = math.max(start_col, math.min(#line, cell.end_col or start_col))
    if end_col > start_col then
      vim.api.nvim_buf_set_extmark(reader_bufnr, visual_namespace, row - 1, start_col, {
        virt_text = { { line:sub(start_col + 1, end_col), "Visual" } },
        virt_text_pos = "overlay",
        hl_mode = "replace",
        right_gravity = false,
        priority = priority,
      })
    end
  end
  return true
end

function M.update_visual_selection(reader_bufnr, winid)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  M.clear_visual_selection(reader_bufnr)
  if not states[reader_bufnr] then
    return false
  end

  winid = winid or states[reader_bufnr].winid
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= reader_bufnr then
    return false
  end
  local state = states[reader_bufnr]
  if vim.api.nvim_get_mode().mode == "\22" and update_logical_cell_visual(reader_bufnr, state) then
    return true
  end
  local mode, first_lnum, last_lnum, first_col, last_col = visual_bounds(reader_bufnr, winid)
  if not mode then
    return false
  end

  local priority = math.max((states[reader_bufnr].config.overlay_priority or 10000) + 1, 10001)
  for lnum = first_lnum, last_lnum do
    local line = vim.api.nvim_buf_get_lines(reader_bufnr, lnum - 1, lnum, false)[1] or ""
    local blockwise = mode == "\22"
    local start_col = mode == "V" and 0 or (blockwise and first_col or (lnum == first_lnum and first_col or 0))
    local end_col = mode == "V" and #line or (blockwise and last_col or (lnum == last_lnum and last_col or #line))
    end_col = math.min(#line, math.max(start_col, end_col + 1))
    if end_col > start_col then
      vim.api.nvim_buf_set_extmark(reader_bufnr, visual_namespace, lnum - 1, start_col, {
        virt_text = { { line:sub(start_col + 1, end_col), "Visual" } },
        virt_text_pos = "overlay",
        hl_mode = "replace",
        right_gravity = false,
        priority = priority,
      })
    end
  end
  return true
end

function M.namespace()
  return namespace
end

function M.visual_namespace()
  return visual_namespace
end

function M._build(source_bufnr, config)
  return build(source_bufnr, config)
end

return M
