local parser = require("markdown-table-wrap.parser")
local render = require("markdown-table-wrap.render")
local mappings = require("markdown-table-wrap.mappings")

local M = {}
local namespace = vim.api.nvim_create_namespace("markdown-table-wrap-reader")
local visual_namespace = vim.api.nvim_create_namespace("markdown-table-wrap-reader-visual")
local states = {}
local source_states = {}

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

local function build(source_bufnr, config)
  local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  local tables = parser.parse_all(source_bufnr)
  local output = {}
  local line_objects = {}
  local reader_to_source = {}
  local source_to_reader = {}
  local table_rows = {}
  local segments = {}
  local table_index = 1
  local source_lnum = 1

  local function append(text, mapped_lnum, line_object, is_table)
    table.insert(output, text)
    local reader_lnum = #output
    line_objects[reader_lnum] = line_object or false
    reader_to_source[reader_lnum] = mapped_lnum
    source_to_reader[mapped_lnum] = source_to_reader[mapped_lnum] or reader_lnum
    table_rows[reader_lnum] = is_table == true
  end

  while source_lnum <= #source_lines do
    local table_info = tables[table_index]
    if table_info and table_info.start_lnum == source_lnum then
      local rendered = render.render_table(table_info, config)
      local reader_start = #output + 1

      for index, text in ipairs(rendered.lines) do
        append(text, rendered.source_lnums[index] or table_info.start_lnum, rendered.line_objects[index], true)
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
  }
end

local function apply_table_highlights(reader_bufnr, built, config)
  vim.api.nvim_buf_clear_namespace(reader_bufnr, namespace, 0, -1)
  require("markdown-table-wrap.theme").apply(config)
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

  for _, lhs in ipairs(state.installed_mappings or {}) do
    pcall(vim.keymap.del, "n", lhs, { buffer = reader_bufnr })
  end
  state.installed_mappings = {}
  state.passthrough_fallbacks = {}

  local config = (((state.config or {}).mappings or {}).reader or {})
  if config.enabled == false then
    return
  end

  local function map(lhs, callback, desc)
    if type(lhs) ~= "string" or lhs == "" then
      return
    end
    vim.keymap.set("n", lhs, callback, { buffer = reader_bufnr, silent = true, desc = desc })
    table.insert(state.installed_mappings, lhs)
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

  require("markdown-table-wrap.cell_ops").install(function(lhs, callback, description)
    map(lhs, callback, description)
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
  vim.b[reader_bufnr].markdown_table_wrap_reader = true
  vim.b[reader_bufnr].markdown_table_wrap_source = source_bufnr
  -- acwrite lets :write save the backing Markdown buffer while modifiable=false
  -- continues to protect the rendered view from direct edits.
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

function M.open(source_bufnr, config)
  source_bufnr = normalize_bufnr(source_bufnr)
  if not vim.api.nvim_buf_is_valid(source_bufnr) or M.is_reader(source_bufnr) then
    return nil
  end

  local winid = vim.api.nvim_get_current_win()
  local source_cursor = vim.api.nvim_win_get_cursor(winid)
  local source_alt_bufnr = vim.fn.bufnr("#")
  local source_options = {
    wrap = vim.wo[winid].wrap,
    linebreak = vim.wo[winid].linebreak,
    breakindent = vim.wo[winid].breakindent,
    conceallevel = vim.wo[winid].conceallevel,
    concealcursor = vim.wo[winid].concealcursor,
  }
  local built = build(source_bufnr, config)
  local reader_bufnr = create_reader_buffer(source_bufnr)
  local source_bufhidden = acquire_source(source_bufnr, reader_bufnr)

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
    source_bufhidden = source_bufhidden,
    source_alt_bufnr = source_alt_bufnr > 0 and source_alt_bufnr or nil,
    gx_fallback = mappings.get(source_bufnr, "gx", "n"),
  })
  set_reader_keymaps(reader_bufnr)

  local switched, switch_err = pcall(vim.api.nvim_win_set_buf, winid, reader_bufnr)
  if not switched then
    release_source(states[reader_bufnr], reader_bufnr)
    states[reader_bufnr] = nil
    vim.api.nvim_buf_delete(reader_bufnr, { force = true })
    vim.notify("MarkdownTableWrap: could not open reader: " .. tostring(switch_err), vim.log.levels.ERROR)
    return nil
  end
  configure_window(winid, config)

  local reader_lnum = built.source_to_reader[source_cursor[1]] or 1
  local reader_line = built.lines[reader_lnum] or ""
  vim.api.nvim_win_set_cursor(winid, { reader_lnum, math.min(source_cursor[2], #reader_line) })
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

  local reader_cursor = vim.api.nvim_win_get_cursor(winid)
  local source_lnum, source_col = source_cursor_for(state, reader_cursor[1], reader_cursor[2])
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
  vim.api.nvim_win_set_cursor(winid, { source_lnum, source_col })

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
  local built = vim.api.nvim_win_call(winid, function()
    return build(state.source_bufnr, state.config)
  end)

  vim.bo[reader_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(reader_bufnr, 0, -1, false, built.lines)
  apply_table_highlights(reader_bufnr, built, state.config)
  vim.bo[reader_bufnr].modifiable = false
  vim.bo[reader_bufnr].readonly = false
  vim.bo[reader_bufnr].modified = vim.bo[state.source_bufnr].modified

  for key, value in pairs(built) do
    state[key] = value
  end
  state.source_changedtick = vim.api.nvim_buf_get_changedtick(state.source_bufnr)

  configure_window(winid, state.config)
  local reader_lnum = state.source_to_reader[source_lnum] or 1
  local line = state.lines[reader_lnum] or ""
  vim.api.nvim_win_set_cursor(winid, { reader_lnum, math.min(cursor[2], #line) })
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

function M.cleanup(reader_bufnr)
  local state = states[reader_bufnr]
  if state then
    M.clear_visual_selection(reader_bufnr)
    restore_window(state)
    states[reader_bufnr] = nil
    release_source(state, reader_bufnr)
    return
  end

  local source_state = source_states[reader_bufnr]
  if source_state then
    local readers = vim.tbl_keys(source_state.readers)
    source_states[reader_bufnr] = nil
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

  local start_row
  local end_row
  local start_col = current.start_col
  local end_col = current.end_col
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

function M.focus_source_cell(reader_bufnr, source_lnum, column_index, table_id)
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
