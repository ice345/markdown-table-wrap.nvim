local parser = require("markdown-table-wrap.parser")
local render = require("markdown-table-wrap.render")

local M = {}
local namespace = vim.api.nvim_create_namespace("markdown-table-wrap-reader")
local states = {}

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
  for _, segment in ipairs(built.segments) do
    render.apply_highlights(reader_bufnr, segment.rendered.line_objects, config, {
      namespace = namespace,
      start_row = segment.start_row,
      clear = false,
    })
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
  local function edit(keys, pause)
    require("markdown-table-wrap.reader").edit(reader_bufnr, keys, pause)
  end

  vim.keymap.set("n", "q", function()
    require("markdown-table-wrap").close_reader()
  end, { buffer = reader_bufnr, silent = true, desc = "Close Markdown table reader" })

  vim.keymap.set("n", "e", function()
    edit(nil, true)
  end, { buffer = reader_bufnr, silent = true, desc = "Edit Markdown source" })

  for _, key in ipairs({ "i", "a", "I", "A", "o", "O" }) do
    vim.keymap.set("n", key, function()
      edit(key, false)
    end, { buffer = reader_bufnr, silent = true, desc = "Edit Markdown source" })
  end

  vim.keymap.set("n", "gx", function()
    require("markdown-table-wrap.reader").open_link(reader_bufnr)
  end, { buffer = reader_bufnr, silent = true, desc = "Open rendered Markdown table link" })
end

local function create_reader_buffer(source_bufnr)
  local reader_bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[reader_bufnr].markdown_table_wrap_reader = true
  vim.b[reader_bufnr].markdown_table_wrap_source = source_bufnr
  -- acwrite lets :write save the backing Markdown buffer while modifiable=false
  -- continues to protect the rendered view from direct edits.
  vim.bo[reader_bufnr].buftype = "acwrite"
  vim.bo[reader_bufnr].bufhidden = "wipe"
  vim.bo[reader_bufnr].swapfile = false
  vim.bo[reader_bufnr].undofile = false
  vim.bo[reader_bufnr].modifiable = true

  pcall(
    vim.api.nvim_buf_set_name,
    reader_bufnr,
    string.format("markdown-table-wrap://reader/%d/%s", reader_bufnr, source_name(source_bufnr))
  )

  vim.bo[reader_bufnr].filetype = vim.bo[source_bufnr].filetype
  set_reader_keymaps(reader_bufnr)
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
  local source_col = state.table_rows[reader_lnum] and 0 or math.min(reader_col, #source_line)
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

function M.open(source_bufnr, config)
  source_bufnr = normalize_bufnr(source_bufnr)
  if not vim.api.nvim_buf_is_valid(source_bufnr) or M.is_reader(source_bufnr) then
    return nil
  end

  local winid = vim.api.nvim_get_current_win()
  local source_cursor = vim.api.nvim_win_get_cursor(winid)
  local source_options = {
    wrap = vim.wo[winid].wrap,
    linebreak = vim.wo[winid].linebreak,
    breakindent = vim.wo[winid].breakindent,
    conceallevel = vim.wo[winid].conceallevel,
    concealcursor = vim.wo[winid].concealcursor,
  }
  local built = build(source_bufnr, config)
  local reader_bufnr = create_reader_buffer(source_bufnr)
  local source_bufhidden = vim.bo[source_bufnr].bufhidden

  vim.api.nvim_buf_set_lines(reader_bufnr, 0, -1, false, built.lines)
  apply_table_highlights(reader_bufnr, built, config)
  vim.bo[reader_bufnr].modifiable = false
  vim.bo[reader_bufnr].readonly = false
  vim.bo[reader_bufnr].modified = vim.bo[source_bufnr].modified

  states[reader_bufnr] = vim.tbl_extend("force", built, {
    source_bufnr = source_bufnr,
    config = config,
    source_options = source_options,
    source_bufhidden = source_bufhidden,
  })

  vim.bo[source_bufnr].bufhidden = "hide"
  local switched, switch_err = pcall(vim.api.nvim_win_set_buf, winid, reader_bufnr)
  if not switched then
    vim.bo[source_bufnr].bufhidden = source_bufhidden
    states[reader_bufnr] = nil
    vim.api.nvim_buf_delete(reader_bufnr, { force = true })
    vim.notify("MarkdownTableWrap: could not open reader: " .. tostring(switch_err), vim.log.levels.ERROR)
    return nil
  end
  configure_window(winid, config)

  local reader_lnum = built.source_to_reader[source_cursor[1]] or 1
  local reader_line = built.lines[reader_lnum] or ""
  vim.api.nvim_win_set_cursor(winid, { reader_lnum, math.min(source_cursor[2], #reader_line) })
  return reader_bufnr
end

function M.close(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return nil
  end

  local winid = vim.api.nvim_get_current_win()
  local reader_cursor = vim.api.nvim_win_get_cursor(winid)
  local source_lnum, source_col = source_cursor_for(state, reader_cursor[1], reader_cursor[2])
  -- The Reader mirrors source's modified flag so :x and ZZ save correctly.
  -- Clear only the disposable mirror before switching away from this view.
  vim.bo[reader_bufnr].modified = false
  vim.api.nvim_win_set_buf(winid, state.source_bufnr)
  vim.bo[state.source_bufnr].bufhidden = state.source_bufhidden or ""

  for option, value in pairs(state.source_options or {}) do
    vim.wo[winid][option] = value
  end
  vim.api.nvim_win_set_cursor(winid, { source_lnum, source_col })

  states[reader_bufnr] = nil
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

  local winids = vim.fn.win_findbuf(reader_bufnr)
  local winid = winids[1]
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

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

  configure_window(winid, state.config)
  local reader_lnum = state.source_to_reader[source_lnum] or 1
  local line = state.lines[reader_lnum] or ""
  vim.api.nvim_win_set_cursor(winid, { reader_lnum, math.min(cursor[2], #line) })
  return true
end

function M.reconfigure(reader_bufnr, config)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return false
  end

  state.config = config
  if #vim.fn.win_findbuf(reader_bufnr) == 0 then
    return true
  end
  return M.refresh(reader_bufnr)
end

function M.open_link(reader_bufnr)
  reader_bufnr = normalize_bufnr(reader_bufnr)
  local state = states[reader_bufnr]
  if not state then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_object = state.line_objects[cursor[1]]
  local links = {}

  for _, chunk in ipairs(type(line_object) == "table" and line_object.chunks or {}) do
    if (chunk.kind == "link" or chunk.kind == "image") and chunk.url and chunk.url ~= "" then
      table.insert(links, chunk)
      if cursor[2] >= chunk.start_col and cursor[2] < chunk.end_col then
        vim.ui.open(chunk.url)
        return true
      end
    end
  end

  if #links == 1 then
    vim.ui.open(links[1].url)
    return true
  end

  vim.notify("MarkdownTableWrap: place the cursor over a rendered table link.", vim.log.levels.INFO)
  return false
end

function M.cleanup(reader_bufnr)
  local state = states[reader_bufnr]
  if state and vim.api.nvim_buf_is_valid(state.source_bufnr) then
    vim.bo[state.source_bufnr].bufhidden = state.source_bufhidden or ""
  end
  states[reader_bufnr] = nil
end

function M.namespace()
  return namespace
end

function M._build(source_bufnr, config)
  return build(source_bufnr, config)
end

return M
