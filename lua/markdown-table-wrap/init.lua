local M = {}

M.version = "0.7.0"

local config_module = require("markdown-table-wrap.config")
M.config = config_module.defaults()
M.state = {
  win = nil,
  buf = nil,
  inline_buf = nil,
  augroup = nil,
  refresh_epoch = 0,
  refresh_tokens = {},
  paused_buffers = {},
  auto_buffers = {},
  buffer_modes = {},
  inline_viewports = {},
  wide_viewports = {},
  buffer_configs = {},
  gx_fallbacks = {},
  gx_installed = {},
  gx_callbacks = {},
  last_signature = {},
  did_setup = false,
  visual_buffers = {},
  float_source_bufnr = nil,
  float_source_winid = nil,
  float_source_alt_bufnr = nil,
  float_rendered = nil,
  float_origin = nil,
}

local function configured_filetypes()
  return config_module.filetypes(M.config.extra_filetypes)
end

local function is_supported_filetype(filetype)
  return vim.tbl_contains(configured_filetypes(), filetype)
end

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function invalidate_scheduled_refresh(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    M.state.refresh_tokens[bufnr] = (M.state.refresh_tokens[bufnr] or 0) + 1
  end
end

local function is_markdown_buffer(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if vim.b[bufnr].markdown_table_wrap_reader == true then
    return false
  end

  return is_supported_filetype(vim.bo[bufnr].filetype)
end

local function is_auto_preview_buffer(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return is_markdown_buffer(bufnr) and vim.b[bufnr].markdown_table_wrap_auxiliary ~= true
end

local function preview_mode_for(bufnr)
  return M.state.buffer_modes[bufnr] or M.config.preview_mode
end

local function auto_preview_for(bufnr)
  local override = M.state.auto_buffers[bufnr]
  if override ~= nil then
    return override
  end
  return M.config.auto_preview
end

local function inline_viewport_for(bufnr)
  local override = M.state.inline_viewports[bufnr]
  if override ~= nil then
    return override
  end
  return M.config.inline_viewport_scrolling
end

local function config_for_buffer(bufnr)
  local preview_mode = preview_mode_for(bufnr)
  local auto_preview = auto_preview_for(bufnr)
  local inline_viewport_scrolling = inline_viewport_for(bufnr)
  local viewport = M.state.wide_viewports[bufnr]
  local viewport_start = viewport and viewport.start_column or nil
  local cached = M.state.buffer_configs[bufnr]
  if
    cached
    and cached.preview_mode == preview_mode
    and cached.auto_preview == auto_preview
    and cached.inline_viewport_scrolling == inline_viewport_scrolling
    and cached.viewport_start == viewport_start
  then
    return cached.config
  end

  local config = vim.deepcopy(M.config)
  config.preview_mode = preview_mode
  config.auto_preview = auto_preview
  config.inline_viewport_scrolling = inline_viewport_scrolling
  if viewport and type(config.wide_table) == "table" and type(config.wide_table.viewport) == "table" then
    config.wide_table.viewport.start_column = viewport.start_column or config.wide_table.viewport.start_column
  end
  M.state.buffer_configs[bufnr] = {
    preview_mode = preview_mode,
    auto_preview = auto_preview,
    inline_viewport_scrolling = inline_viewport_scrolling,
    viewport_start = viewport_start,
    config = config,
  }
  return config
end

function M.get_buffer_config(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return vim.deepcopy(config_for_buffer(bufnr))
end

function M.get_preview_mode(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return preview_mode_for(bufnr)
end

function M.get_state(bufnr)
  local context, err = require("markdown-table-wrap.context").resolve({ bufnr = bufnr })
  if not context then
    return nil, err
  end
  return context
end

function M.resolve_source_buffer(bufnr)
  local context = require("markdown-table-wrap.context").resolve({ bufnr = bufnr })
  return context and context.source_bufnr or nil
end

---@param name string
---@param opts? table
---@return boolean
function M.action(name, opts)
  return require("markdown-table-wrap.actions").run(name, opts)
end

---@param opts? table
---@return boolean, string?
function M.copy_rendered_cell(opts)
  return require("markdown-table-wrap.export").cell(opts)
end

---@param opts? table
---@return boolean, string?
function M.copy_rendered_table(opts)
  return require("markdown-table-wrap.export").table(opts)
end

---@param opts? table
---@return boolean, string?
function M.export_table(opts)
  return require("markdown-table-wrap.export").export(opts)
end

function M.edit_table(action, opts)
  local editor = require("markdown-table-wrap.table_edit")
  local fn = editor[action]
  if type(fn) ~= "function" then
    return false
  end
  return fn(opts or {})
end

---@param bufnr? integer
---@return string
function M.statusline(bufnr)
  local ok, context = pcall(require("markdown-table-wrap.context").resolve, { bufnr = bufnr })
  if not ok or not context then
    return ""
  end

  local mode = context.mode:sub(1, 1):upper() .. context.mode:sub(2)
  if not context.table then
    return "MTW " .. mode
  end
  local table_row = context.cell and context.cell.row_index ~= nil and context.cell.row_index + 1
    or context.cursor.source_lnum - context.table.start_lnum + 1
  local cell = context.cell and context.cell.index or 0
  return string.format("MTW %s T%d:C%d", mode, math.max(1, table_row), cell)
end

local function current_gx_mapping(bufnr)
  return require("markdown-table-wrap.mappings").get(bufnr, "gx", "n")
end

local function owns_gx_mapping(bufnr, mapping)
  local callback = M.state.gx_callbacks[bufnr]
  return M.state.gx_installed[bufnr] == true and callback ~= nil and mapping and mapping.callback == callback
end

local function restore_gx_mapping(bufnr)
  if not M.state.gx_installed[bufnr] then
    return
  end

  local fallback = M.state.gx_fallbacks[bufnr]
  local current = vim.api.nvim_buf_is_valid(bufnr) and current_gx_mapping(bufnr) or nil
  if owns_gx_mapping(bufnr, current) then
    require("markdown-table-wrap.mappings").restore(bufnr, "gx", "n", fallback)
  end
  M.state.gx_fallbacks[bufnr] = nil
  M.state.gx_installed[bufnr] = nil
  M.state.gx_callbacks[bufnr] = nil
end

local function invoke_gx_mapping(mapping, bufnr)
  return require("markdown-table-wrap.mappings").invoke(mapping, { native_gx = true, context_bufnr = bufnr })
end

local function attach_link_keymap(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if
    not M.config.map_gx
    or vim.b[bufnr].markdown_table_wrap_reader == true
    or not is_supported_filetype(vim.bo[bufnr].filetype)
  then
    restore_gx_mapping(bufnr)
    return
  end

  local current = current_gx_mapping(bufnr)
  if not owns_gx_mapping(bufnr, current) then
    M.state.gx_fallbacks[bufnr] = current
  end

  local proxy = function()
    local parser = require("markdown-table-wrap.parser")
    local current_bufnr = vim.api.nvim_get_current_buf()
    local table_info = parser.parse_at_cursor(current_bufnr, vim.api.nvim_win_get_cursor(0)[1])
    if table_info then
      require("markdown-table-wrap.nav").open_link()
      return
    end
    invoke_gx_mapping(M.state.gx_fallbacks[current_bufnr], current_bufnr)
  end
  vim.keymap.set("n", "gx", proxy, { buffer = bufnr, silent = true, desc = "Open Markdown table link" })
  M.state.gx_installed[bufnr] = true
  M.state.gx_callbacks[bufnr] = proxy
end

local function close_existing(opts)
  opts = opts or {}
  local source_bufnr = M.state.float_source_bufnr
  local source_winid = M.state.float_source_winid
  local origin = M.state.float_origin
  local float_winid = M.state.win
  local float_bufnr = M.state.buf
  local had_float = source_bufnr ~= nil
  M.state.win = nil
  M.state.buf = nil
  M.state.float_source_bufnr = nil
  M.state.float_source_winid = nil
  M.state.float_source_alt_bufnr = nil
  M.state.float_rendered = nil
  M.state.float_origin = nil

  if float_winid and float_winid ~= opts.skip_win and vim.api.nvim_win_is_valid(float_winid) then
    pcall(vim.api.nvim_win_close, float_winid, true)
  end
  if float_bufnr and float_bufnr ~= opts.skip_buf and vim.api.nvim_buf_is_valid(float_bufnr) then
    pcall(vim.api.nvim_buf_delete, float_bufnr, { force = true })
  end
  if had_float and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
    require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", {
      mode = "source",
      source_bufnr = source_bufnr,
      view_bufnr = source_bufnr,
      winid = source_winid,
    })
  end
  return source_bufnr, source_winid, origin
end

local function table_signature(bufnr, table_info, config)
  local lines = vim.api.nvim_buf_get_lines(bufnr, table_info.start_lnum - 1, table_info.end_lnum, false)
  return table.concat({
    tostring(table_info.start_lnum),
    tostring(table_info.end_lnum),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(config.max_width_ratio),
    tostring(config.min_col_width),
    tostring(config.max_col_width),
    config.use_unicode_border and "unicode" or "ascii",
    tostring(config.table_border),
    tostring(config.row_separator),
    tostring(config.inline_mode),
    tostring(config.clear_on_visual),
    tostring(config.inline_virtual_text),
    tostring(config.inline_disable_wrap),
    tostring(config.inline_wrap_scope),
    tostring(config.inline_viewport_scrolling),
    config_module.wide_table_signature(config.wide_table),
    table.concat(lines, "\n"),
  }, "\31")
end

local function all_tables_signature(bufnr, tables, config)
  local parts = {
    tostring(vim.api.nvim_buf_get_changedtick(bufnr)),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(config.max_width_ratio),
    tostring(config.min_col_width),
    tostring(config.max_col_width),
    config.use_unicode_border and "unicode" or "ascii",
    tostring(config.table_border),
    tostring(config.row_separator),
    tostring(config.inline_mode),
    tostring(config.clear_on_visual),
    tostring(config.inline_virtual_text),
    tostring(config.inline_disable_wrap),
    tostring(config.inline_wrap_scope),
    tostring(config.overlay_fill),
    tostring(config.inline_viewport_scrolling),
    config_module.wide_table_signature(config.wide_table),
  }

  for _, table_info in ipairs(tables) do
    table.insert(parts, tostring(table_info.start_lnum))
    table.insert(parts, tostring(table_info.end_lnum))
  end

  return table.concat(parts, "\31")
end

local restore_float_origin

function M.close_preview(opts)
  opts = opts or {}
  if require("markdown-table-wrap.reader").is_reader(0) then
    M.close_reader()
    return true
  end

  if M.state.float_source_bufnr then
    local source_bufnr, source_winid, origin = close_existing()
    if opts.restore_origin ~= false and origin and restore_float_origin(source_bufnr, source_winid, origin) then
      return true
    end
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    elseif source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
      vim.api.nvim_win_set_buf(0, source_bufnr)
    end
    if source_bufnr and opts.pause ~= false then
      M.pause_buffer(source_bufnr)
    end
    return source_bufnr ~= nil
  end

  close_existing()
  local bufnr = vim.api.nvim_get_current_buf()
  require("markdown-table-wrap.inline").clear(bufnr)
  if M.state.inline_buf == bufnr then
    M.state.inline_buf = nil
  end
  M.state.paused_buffers[bufnr] = true
  return true
end

local function table_under_cursor(opts)
  opts = opts or {}

  if not is_markdown_buffer() then
    if not opts.silent then
      vim.notify(
        "MarkdownTableWrap: preview is only available in Markdown buffers or fts added to extra_filetypes in opts.",
        vim.log.levels.INFO
      )
    end
    return nil
  end

  local parser = require("markdown-table-wrap.parser")
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info, err = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if not opts.silent then
      vim.notify(err or "MarkdownTableWrap: cursor is not inside a Markdown pipe table.", vim.log.levels.INFO)
    end
    return nil
  end

  return bufnr, table_info
end

local function prepare_preview_source()
  local current = vim.api.nvim_get_current_buf()
  local reader = require("markdown-table-wrap.reader")
  local is_reader = reader.is_reader(current)
  local is_float = M.state.buf == current and M.state.float_source_bufnr ~= nil
  local context = select(1, require("markdown-table-wrap.context").resolve({ bufnr = current }))
  if not is_reader and not is_float then
    return context, true
  end
  if not context then
    return nil, false
  end

  local source_bufnr = context.source_bufnr
  if is_reader then
    if not reader.close(current) then
      return nil, false
    end
  else
    local source_winid = context.float and context.float.source_winid or M.state.float_source_winid
    close_existing()
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    elseif vim.api.nvim_buf_is_valid(source_bufnr) then
      vim.api.nvim_win_set_buf(0, source_bufnr)
    end
  end

  if vim.api.nvim_get_current_buf() ~= source_bufnr then
    return nil, false
  end
  local lnum = math.max(1, math.min(context.cursor.source_lnum, vim.api.nvim_buf_line_count(source_bufnr)))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, lnum - 1, lnum, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, math.min(context.cursor.source_col, #line)) })
  return context, true
end

local function focus_float_origin(rendered, winid, context)
  local cell = context and context.cell or nil
  if not cell or not cell.table_id or cell.row_index == nil or not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  for row, object in ipairs(rendered.line_objects or {}) do
    for _, rendered_cell in ipairs(type(object) == "table" and object.cells or {}) do
      if
        rendered_cell.table_id == cell.table_id
        and rendered_cell.row_index == cell.row_index
        and rendered_cell.column_index == cell.index
      then
        vim.api.nvim_win_set_cursor(winid, { row, rendered_cell.start_col })
        return
      end
    end
  end
end

local function float_origin_from_context(context)
  if not context or not context.source_bufnr then
    return nil
  end
  return {
    mode = context.mode,
    source_bufnr = context.source_bufnr,
    paused = M.state.paused_buffers[context.source_bufnr] == true,
    cursor = {
      source_lnum = context.cursor.source_lnum,
      source_col = context.cursor.source_col,
    },
    cell = context.cell and {
      table_id = context.cell.table_id,
      row_index = context.cell.row_index,
      index = context.cell.index,
    } or nil,
  }
end

function M.inline_preview()
  local _, prepared = prepare_preview_source()
  if not prepared then
    return false
  end
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return false
  end

  close_existing()
  M.state.paused_buffers[bufnr] = nil
  local config = config_for_buffer(bufnr)
  require("markdown-table-wrap.inline").show(bufnr, table_info, config)
  M.state.last_signature[bufnr] = table_signature(bufnr, table_info, config)
  M.state.inline_buf = bufnr
  local event_data =
    { mode = "inline", source_bufnr = bufnr, view_bufnr = bufnr, winid = vim.api.nvim_get_current_win() }
  require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", event_data)
  return true
end

function M.reader_preview(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local reader = require("markdown-table-wrap.reader")

  if reader.is_reader(bufnr) then
    return bufnr
  end

  local _, prepared = prepare_preview_source()
  if not prepared then
    return nil
  end
  bufnr = vim.api.nvim_get_current_buf()

  if not is_markdown_buffer() then
    if not opts.silent then
      vim.notify("MarkdownTableWrap: reader mode is only available in Markdown buffers.", vim.log.levels.INFO)
    end
    return nil
  end

  if not opts.auto then
    M.state.buffer_modes[bufnr] = "reader"
  end

  close_existing()
  require("markdown-table-wrap.inline").clear(bufnr)
  M.state.inline_buf = nil
  M.state.last_signature[bufnr] = nil
  M.state.paused_buffers[bufnr] = nil
  return reader.open(bufnr, config_for_buffer(bufnr))
end

restore_float_origin = function(source_bufnr, source_winid, origin)
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) or origin.source_bufnr ~= source_bufnr then
    return false
  end

  if source_winid and vim.api.nvim_win_is_valid(source_winid) then
    vim.api.nvim_set_current_win(source_winid)
  elseif vim.api.nvim_get_current_buf() ~= source_bufnr then
    vim.api.nvim_win_set_buf(0, source_bufnr)
  end
  if vim.api.nvim_get_current_buf() ~= source_bufnr then
    return false
  end

  local cursor = origin.cursor or {}
  local lnum = math.max(1, math.min(cursor.source_lnum or 1, vim.api.nvim_buf_line_count(source_bufnr)))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, lnum - 1, lnum, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, math.min(cursor.source_col or 0, #line)) })
  invalidate_scheduled_refresh(source_bufnr)

  if origin.mode == "reader" then
    M.state.paused_buffers[source_bufnr] = nil
    local reader_bufnr = M.reader_preview({ silent = true, auto = true })
    if not reader_bufnr then
      return false
    end
    local cell = origin.cell
    if cell and cell.index and cell.row_index ~= nil then
      require("markdown-table-wrap.reader").focus_source_cell(
        reader_bufnr,
        lnum,
        cell.index,
        cell.table_id,
        cell.row_index
      )
    end
  elseif origin.mode == "inline" and not require("markdown-table-wrap.inline").is_active(source_bufnr) then
    if not M.inline_preview() then
      return false
    end
  end

  M.state.paused_buffers[source_bufnr] = origin.paused and true or nil
  return true
end

function M.pause_buffer(bufnr)
  bufnr = normalize_bufnr(bufnr)
  M.state.paused_buffers[bufnr] = true
  M.state.last_signature[bufnr] = nil
end

function M.close_reader()
  local reader = require("markdown-table-wrap.reader")
  local bufnr = vim.api.nvim_get_current_buf()
  if not reader.is_reader(bufnr) then
    return false
  end

  local source_bufnr = reader.close(bufnr)
  if source_bufnr then
    M.pause_buffer(source_bufnr)
    return true
  end
  return false
end

function M.toggle_reader()
  if require("markdown-table-wrap.reader").is_reader(0) then
    return M.close_reader()
  end
  return M.reader_preview()
end

function M.edit_source()
  local reader = require("markdown-table-wrap.reader")
  if not reader.is_reader(0) then
    return false
  end
  return reader.edit(0, nil, true)
end

function M.float_preview(opts)
  opts = opts or {}
  local previous_origin = M.state.float_origin and vim.deepcopy(M.state.float_origin) or nil
  local origin_context, prepared = prepare_preview_source()
  if not prepared then
    return false
  end
  local float_origin = opts.origin
    or (origin_context and origin_context.mode == "float" and previous_origin)
    or float_origin_from_context(origin_context)
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return false
  end

  close_existing()

  local source_winid = vim.api.nvim_get_current_win()
  local source_alt_bufnr = vim.fn.bufnr("#")
  local config = config_for_buffer(bufnr)
  local render = require("markdown-table-wrap.render")
  local rendered = render.render_table(table_info, config)
  local buf, win = render.open_float(rendered, config)
  M.state.buf = buf
  M.state.win = win
  M.state.float_source_bufnr = bufnr
  M.state.float_source_winid = source_winid
  M.state.float_source_alt_bufnr = source_alt_bufnr > 0 and source_alt_bufnr or nil
  M.state.float_rendered = rendered
  M.state.float_origin = float_origin
  focus_float_origin(rendered, win, origin_context)
  local event_data = { mode = "float", source_bufnr = bufnr, view_bufnr = buf, winid = win }
  require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)
  require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", event_data)
  return buf, win
end

function M.preview()
  local context = select(1, require("markdown-table-wrap.context").resolve())
  local mode = preview_mode_for(context and context.source_bufnr or vim.api.nvim_get_current_buf())
  if mode == "float" then
    M.float_preview()
    return
  end

  if mode == "reader" then
    M.reader_preview()
    return
  end

  M.inline_preview()
end

function M.refresh_auto(opts)
  opts = opts or {}
  local bufnr = normalize_bufnr(opts.bufnr)
  local inline = require("markdown-table-wrap.inline")
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end

  -- Reader -> Float briefly restores the Source window. That BufWinEnter can
  -- leave an automatic Reader refresh queued for the same Source. An explicit
  -- Float is authoritative while its window is alive; otherwise the delayed
  -- callback immediately closes it and makes the keypress appear to do
  -- nothing.
  if M.state.float_source_bufnr == bufnr and M.state.win ~= nil and vim.api.nvim_win_is_valid(M.state.win) then
    return
  end
  local config = config_for_buffer(bufnr)

  if not config.auto_preview and not opts.force then
    return
  end

  if M.state.paused_buffers[bufnr] and not opts.force then
    return
  end

  if not is_markdown_buffer(bufnr) or (not opts.force and not is_auto_preview_buffer(bufnr)) then
    inline.clear(bufnr)
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  if not config.auto_preview_in_insert and mode:match("^i") then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    return
  end

  if mode:match("^[vV\22]") then
    return
  end

  local parser = require("markdown-table-wrap.parser")
  if config.preview_mode == "reader" then
    local reader = require("markdown-table-wrap.reader")
    if reader.has_source_readers(bufnr) then
      reader.refresh_source(bufnr)
      return
    end
    if config.reader.auto_open == "has_table" and #parser.parse_all(bufnr) == 0 then
      inline.clear(bufnr)
      M.state.last_signature[bufnr] = nil
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      return
    end
    M.reader_preview({ silent = true, auto = true })
    return
  end

  if config.render_all then
    local tables = parser.parse_all(bufnr)
    if #tables == 0 then
      inline.clear(bufnr)
      M.state.inline_buf = nil
      M.state.last_signature[bufnr] = nil
      return
    end

    local signature = all_tables_signature(bufnr, tables, config)
    if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
      inline.attach_window(bufnr)
      return
    end

    close_existing()
    inline.show_many(bufnr, tables, config)
    M.state.last_signature[bufnr] = signature
    M.state.inline_buf = bufnr
    local event_data = {
      mode = "inline",
      source_bufnr = bufnr,
      view_bufnr = bufnr,
      winid = vim.api.nvim_get_current_win(),
    }
    require("markdown-table-wrap.events").emit("MarkdownTableWrapViewChanged", event_data)
    require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", event_data)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if config.clear_on_cursor_leave ~= false then
      inline.clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end
    return
  end

  local signature = table_signature(bufnr, table_info, config)
  if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
    inline.attach_window(bufnr)
    return
  end

  close_existing()
  inline.show(bufnr, table_info, config)
  M.state.last_signature[bufnr] = signature
  M.state.inline_buf = bufnr
  require("markdown-table-wrap.events").emit("MarkdownTableWrapRendered", {
    mode = "inline",
    source_bufnr = bufnr,
    view_bufnr = bufnr,
    winid = vim.api.nvim_get_current_win(),
  })
end

function M.schedule_refresh(opts)
  opts = vim.deepcopy(opts or {})
  local bufnr = normalize_bufnr(opts.bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local winid = opts.winid
  if not winid and vim.api.nvim_get_current_buf() == bufnr then
    winid = vim.api.nvim_get_current_win()
  end
  opts.bufnr = bufnr
  opts.winid = nil

  M.state.refresh_tokens[bufnr] = (M.state.refresh_tokens[bufnr] or 0) + 1
  local token = M.state.refresh_tokens[bufnr]
  local epoch = M.state.refresh_epoch
  local delay = opts.immediate and 0 or M.config.debounce_ms

  vim.defer_fn(function()
    if
      epoch ~= M.state.refresh_epoch
      or token ~= M.state.refresh_tokens[bufnr]
      or not vim.api.nvim_buf_is_valid(bufnr)
    then
      return
    end

    if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
      winid = vim.fn.win_findbuf(bufnr)[1]
    end
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      return
    end

    local ok, err = pcall(vim.api.nvim_win_call, winid, function()
      M.refresh_auto(opts)
    end)
    if not ok and vim.api.nvim_buf_is_valid(bufnr) then
      vim.notify("MarkdownTableWrap: scheduled refresh failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, delay)
end

function M.toggle_preview()
  if require("markdown-table-wrap.reader").is_reader(0) then
    M.close_reader()
    return
  end

  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    return M.close_preview()
  end

  local inline = require("markdown-table-wrap.inline")
  local bufnr = vim.api.nvim_get_current_buf()
  if inline.is_active(bufnr) then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    M.state.paused_buffers[bufnr] = true
    return
  end

  M.preview()
end

function M.toggle_inline()
  local inline = require("markdown-table-wrap.inline")
  local reader = require("markdown-table-wrap.reader")
  local bufnr = vim.api.nvim_get_current_buf()

  if reader.is_reader(bufnr) then
    local source_bufnr = reader.source_bufnr(bufnr)
    if not M.close_reader() then
      return false
    end
    bufnr = source_bufnr
  elseif M.state.buf == bufnr and M.state.float_source_bufnr then
    local _, prepared = prepare_preview_source()
    if not prepared then
      return false
    end
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not is_markdown_buffer() then
    vim.notify("MarkdownTableWrap: inline rendering is only available in Markdown buffers.", vim.log.levels.INFO)
    return false
  end

  if inline.is_active(bufnr) then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    M.state.paused_buffers[bufnr] = true
    return false
  end

  M.state.buffer_modes[bufnr] = "inline"
  M.state.auto_buffers[bufnr] = true
  M.state.paused_buffers[bufnr] = nil
  M.refresh_auto({ force = true })
  return true
end

function M.enable_auto_preview()
  local context = select(1, require("markdown-table-wrap.context").resolve())
  if not context then
    return false
  end
  local source_bufnr = context.source_bufnr
  M.state.paused_buffers[source_bufnr] = nil
  M.state.auto_buffers[source_bufnr] = true
  invalidate_scheduled_refresh(source_bufnr)

  if context.mode == "reader" then
    return require("markdown-table-wrap.reader").refresh(context.view_bufnr)
  elseif context.mode == "float" then
    if M.state.float_origin then
      M.state.float_origin.paused = false
    end
    return true
  end
  M.refresh_auto({ bufnr = source_bufnr, force = true })
  return true
end

function M.disable_auto_preview()
  local context = select(1, require("markdown-table-wrap.context").resolve())
  if not context then
    return false
  end
  local source_bufnr = context.source_bufnr
  M.state.paused_buffers[source_bufnr] = true
  M.state.auto_buffers[source_bufnr] = false
  invalidate_scheduled_refresh(source_bufnr)

  if context.mode == "reader" then
    require("markdown-table-wrap.reader").close(context.view_bufnr)
  elseif context.mode == "float" then
    M.close_preview({ restore_origin = false })
  end
  require("markdown-table-wrap.inline").clear(source_bufnr)
  if M.state.inline_buf == source_bufnr then
    M.state.inline_buf = nil
  end
  M.state.last_signature[source_bufnr] = nil
  return true
end

function M.toggle_auto_preview()
  local context = select(1, require("markdown-table-wrap.context").resolve())
  if not context then
    return false
  end
  local source_bufnr = context.source_bufnr
  if auto_preview_for(source_bufnr) and not M.state.paused_buffers[source_bufnr] then
    return M.disable_auto_preview()
  else
    return M.enable_auto_preview()
  end
end

function M.toggle_inline_viewport_scrolling()
  local context = select(1, require("markdown-table-wrap.context").resolve())
  if not context then
    return false
  end
  local source_bufnr = context.source_bufnr
  M.state.inline_viewports[source_bufnr] = not inline_viewport_for(source_bufnr)
  require("markdown-table-wrap.inline").reset_view(source_bufnr)
  M.state.last_signature[source_bufnr] = nil
  if context.mode == "source" or context.mode == "inline" then
    M.refresh_auto({ bufnr = source_bufnr, force = true })
  end
  vim.notify(
    string.format(
      "MarkdownTableWrap: inline viewport scrolling %s",
      inline_viewport_for(source_bufnr) and "enabled" or "disabled"
    ),
    vim.log.levels.INFO
  )
  return true
end

local function wide_viewport_source()
  local reader = require("markdown-table-wrap.reader")
  local bufnr = vim.api.nvim_get_current_buf()
  if reader.is_reader(bufnr) then
    return reader.source_bufnr(bufnr), bufnr
  end
  if M.state.buf == bufnr and M.state.float_source_bufnr then
    return M.state.float_source_bufnr, bufnr
  end
  return bufnr, bufnr
end

local function refresh_float_view(source_bufnr)
  if
    M.state.buf == nil
    or not vim.api.nvim_buf_is_valid(M.state.buf)
    or M.state.win == nil
    or not vim.api.nvim_win_is_valid(M.state.win)
    or M.state.float_source_bufnr ~= source_bufnr
  then
    return false
  end
  local lnum = (M.state.float_rendered or {}).start_lnum
  local table_info = lnum and require("markdown-table-wrap.parser").parse_at_cursor(source_bufnr, lnum) or nil
  if not table_info then
    return false
  end
  local render = require("markdown-table-wrap.render")
  local rendered = render.render_table(table_info, config_for_buffer(source_bufnr))
  local ok = render.update_float(M.state.buf, rendered, config_for_buffer(source_bufnr))
  if not ok then
    return false
  end
  M.state.float_rendered = rendered
  return true
end

function M.set_wide_table_viewport(start_column, bufnr)
  bufnr = bufnr or select(1, wide_viewport_source())
  bufnr = normalize_bufnr(bufnr)
  local start = tonumber(start_column)
  if not start then
    return false
  end
  start = math.max(1, math.floor(start))
  M.state.wide_viewports[bufnr] = { start_column = start }
  local current = vim.api.nvim_get_current_buf()
  local reader = require("markdown-table-wrap.reader")
  if reader.is_reader(current) and reader.source_bufnr(current) == bufnr then
    reader.reconfigure(current, config_for_buffer(bufnr))
  elseif M.state.buf == current and M.state.float_source_bufnr == bufnr then
    return refresh_float_view(bufnr)
  elseif current == bufnr then
    M.state.last_signature[bufnr] = nil
    M.refresh_auto({ bufnr = bufnr, force = true })
  end
  return true
end

function M.shift_wide_table_viewport(delta, bufnr)
  bufnr = bufnr or select(1, wide_viewport_source())
  bufnr = normalize_bufnr(bufnr)
  local config = config_for_buffer(bufnr)
  if (config.wide_table or {}).mode ~= "viewport" then
    vim.notify(
      "MarkdownTableWrap: column viewport movement is available only when wide_table.mode = 'viewport'",
      vim.log.levels.INFO
    )
    return false
  end
  local current = tonumber((config.wide_table or {}).viewport and config.wide_table.viewport.start_column) or 1
  return M.set_wide_table_viewport(current + (tonumber(delta) or 0), bufnr)
end

function M.scroll_view(delta)
  if require("markdown-table-wrap.inline").scroll(vim.api.nvim_get_current_buf(), delta) then
    return
  end

  local key = delta > 0 and "<C-e>" or "<C-y>"
  local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
  vim.cmd("normal! " .. tostring(math.max(1, math.abs(delta))) .. keys)
end

function M.scroll_view_to(position)
  if require("markdown-table-wrap.inline").scroll_to(vim.api.nvim_get_current_buf(), position) then
    return
  end

  if position == "bottom" then
    vim.cmd("normal! G")
  else
    vim.cmd("normal! gg")
  end
end

local function create_autocmds()
  if M.state.augroup then
    vim.api.nvim_del_augroup_by_id(M.state.augroup)
  end

  M.state.augroup = vim.api.nvim_create_augroup("MarkdownTableWrap", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M.state.augroup,
    callback = function(args)
      local reader = require("markdown-table-wrap.reader")
      if reader.is_reader(args.buf) then
        reader.update_visual_selection(args.buf)
        reader.update_sticky_header(args.buf)
        return
      end
      reader.invalidate_source_view(args.buf, vim.api.nvim_get_current_win())
      if not is_auto_preview_buffer(args.buf) then
        return
      end

      require("markdown-table-wrap.inline").update_wrap_for_cursor(args.buf)

      if config_for_buffer(args.buf).render_all then
        return
      end

      M.schedule_refresh({ bufnr = args.buf, winid = vim.api.nvim_get_current_win(), silent = true })
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = M.state.augroup,
    callback = function(args)
      local bufnr = args.buf ~= 0 and args.buf or vim.api.nvim_get_current_buf()
      require("markdown-table-wrap.reader").invalidate_source_view(bufnr, vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWinEnter" }, {
    group = M.state.augroup,
    callback = function(args)
      local bufnr = args.buf
      if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        bufnr = vim.api.nvim_get_current_buf()
      end
      if require("markdown-table-wrap.reader").is_reader(bufnr) then
        return
      end

      require("markdown-table-wrap.reader").invalidate_source_view(bufnr)

      if not is_auto_preview_buffer(bufnr) then
        return
      end
      if args.event == "TextChanged" or args.event == "TextChangedI" or args.event == "InsertLeave" then
        if require("markdown-table-wrap.reader").refresh_source(bufnr) > 0 then
          return
        end
      end
      local winid = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(winid) ~= bufnr then
        winid = nil
      end
      M.schedule_refresh({ bufnr = bufnr, winid = winid, silent = true })
    end,
  })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = M.state.augroup,
    callback = function(args)
      local winids
      if args.event == "WinResized" and type(vim.v.event.windows) == "table" and #vim.v.event.windows > 0 then
        winids = vim.deepcopy(vim.v.event.windows)
      else
        winids = vim.api.nvim_list_wins()
      end

      local reader = require("markdown-table-wrap.reader")
      reader.refresh_windows(winids)
      local scheduled = {}
      for _, winid in ipairs(winids) do
        if vim.api.nvim_win_is_valid(winid) then
          local bufnr = vim.api.nvim_win_get_buf(winid)
          if not scheduled[bufnr] and not reader.is_reader(bufnr) and is_auto_preview_buffer(bufnr) then
            scheduled[bufnr] = true
            M.schedule_refresh({ bufnr = bufnr, winid = winid, silent = true })
          end
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = M.state.augroup,
    callback = function(args)
      local config = config_for_buffer(args.buf)
      if config.auto_preview_in_insert or not config.clear_on_insert then
        return
      end

      local bufnr = args.buf
      require("markdown-table-wrap.inline").clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = M.state.augroup,
    callback = function(args)
      local bufnr = args.buf
      local reader = require("markdown-table-wrap.reader")
      if reader.is_reader(bufnr) then
        local mode = vim.api.nvim_get_mode().mode
        if not mode:match("^[vV\22]") then
          require("markdown-table-wrap.cell_ops").clear_visual(bufnr)
        end
        reader.update_visual_selection(bufnr)
        reader.update_sticky_header(bufnr)
        return
      end
      if not is_markdown_buffer(bufnr) or config_for_buffer(bufnr).clear_on_visual == false then
        return
      end

      local mode = vim.api.nvim_get_mode().mode
      local visual = mode:match("^[vV\22]") ~= nil

      if visual then
        require("markdown-table-wrap.inline").clear(bufnr)
        if M.state.inline_buf == bufnr then
          M.state.inline_buf = nil
        end
        M.state.last_signature[bufnr] = nil
        M.state.visual_buffers[bufnr] = true
      elseif M.state.visual_buffers[bufnr] then
        M.state.visual_buffers[bufnr] = nil
        M.schedule_refresh({ bufnr = bufnr, winid = vim.api.nvim_get_current_win(), silent = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = M.state.augroup,
    callback = function(args)
      local windows = vim.fn.win_findbuf(args.buf)
      if #windows == 0 then
        windows = { vim.api.nvim_get_current_win() }
      end
      for _, winid in ipairs(windows) do
        require("markdown-table-wrap.inline").attach_window(args.buf, { restore_view = true, winid = winid })
        require("markdown-table-wrap.reader").restore_source_view(args.buf, winid)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = M.state.augroup,
    callback = function(args)
      local reader = require("markdown-table-wrap.reader")
      if reader.is_reader(args.buf) then
        require("markdown-table-wrap.cell_ops").clear_visual(args.buf)
        reader.clear_visual_selection(args.buf)
        return
      end
      require("markdown-table-wrap.inline").detach_window(vim.api.nvim_get_current_win())
      local config = config_for_buffer(args.buf)
      if config.render_all then
        return
      end

      if config.clear_on_cursor_leave ~= false then
        require("markdown-table-wrap.inline").clear(args.buf)
        if M.state.inline_buf == args.buf then
          M.state.inline_buf = nil
        end
        M.state.last_signature[args.buf] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = M.state.augroup,
    callback = function(args)
      if args.buf == M.state.buf then
        close_existing({ skip_buf = args.buf })
      elseif args.buf == M.state.float_source_bufnr then
        close_existing()
      end
      require("markdown-table-wrap.cell_ops").cleanup(args.buf)
      require("markdown-table-wrap.reader").cleanup(args.buf)
      require("markdown-table-wrap.inline").dispose(args.buf)
      require("markdown-table-wrap.cache").clear_buffer(args.buf)
      require("markdown-table-wrap.discovery").clear(args.buf)
      M.state.refresh_tokens[args.buf] = nil
      M.state.paused_buffers[args.buf] = nil
      M.state.auto_buffers[args.buf] = nil
      M.state.buffer_modes[args.buf] = nil
      M.state.inline_viewports[args.buf] = nil
      M.state.wide_viewports[args.buf] = nil
      M.state.buffer_configs[args.buf] = nil
      M.state.gx_fallbacks[args.buf] = nil
      M.state.gx_installed[args.buf] = nil
      M.state.gx_callbacks[args.buf] = nil
      M.state.last_signature[args.buf] = nil
      M.state.visual_buffers[args.buf] = nil
      if M.state.inline_buf == args.buf then
        M.state.inline_buf = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = M.state.augroup,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid and winid == M.state.win then
        close_existing({ skip_win = winid })
      end
      require("markdown-table-wrap.inline").detach_window(winid)
      require("markdown-table-wrap.inline").clear_window_views(winid)
      require("markdown-table-wrap.reader").clear_saved_views(nil, winid)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = M.state.augroup,
    callback = function()
      require("markdown-table-wrap.theme").apply(M.config)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = M.state.augroup,
    pattern = "*",
    callback = function(args)
      attach_link_keymap(args.buf)
    end,
  })
end

---@param opts? MarkdownTableWrapSetupOptions
function M.setup(opts)
  local setup_opts = vim.deepcopy(opts or {})
  local reset_state = setup_opts.reset_state == true
  setup_opts.reset_state = nil

  if M.state.did_setup then
    close_existing()
    local inline = require("markdown-table-wrap.inline")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        inline.dispose(bufnr)
      end
    end
  end

  M.config = config_module.resolve(setup_opts)
  local unknown = config_module.unknown_options(opts)
  if #unknown > 0 then
    vim.notify("MarkdownTableWrap: unknown setup option(s): " .. table.concat(unknown, ", "), vim.log.levels.WARN)
  end
  require("markdown-table-wrap.cache").clear()
  require("markdown-table-wrap.cache").configure(M.config.cache)
  require("markdown-table-wrap.discovery").configure(M.config.discovery)
  M.state.refresh_epoch = M.state.refresh_epoch + 1
  M.state.refresh_tokens = {}
  if reset_state then
    M.state.paused_buffers = {}
    M.state.auto_buffers = {}
    M.state.buffer_modes = {}
    M.state.inline_viewports = {}
    M.state.wide_viewports = {}
  end
  M.state.buffer_configs = {}
  M.state.last_signature = {}
  M.state.visual_buffers = {}
  M.state.inline_buf = nil
  require("markdown-table-wrap.reader").clear_saved_views()
  create_autocmds()
  require("markdown-table-wrap.commands").register(M)
  require("markdown-table-wrap.theme").apply(M.config)
  M.state.did_setup = true

  local reader = require("markdown-table-wrap.reader")
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if reader.is_reader(bufnr) then
      local source_bufnr = reader.source_bufnr(bufnr)
      if source_bufnr then
        reader.reconfigure(bufnr, config_for_buffer(source_bufnr))
      end
    end
    attach_link_keymap(bufnr)
  end

  if auto_preview_for(vim.api.nvim_get_current_buf()) and is_auto_preview_buffer() then
    M.schedule_refresh({
      bufnr = vim.api.nvim_get_current_buf(),
      winid = vim.api.nvim_get_current_win(),
      silent = true,
      immediate = true,
    })
  end
end

return M
