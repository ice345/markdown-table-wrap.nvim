local width = require("markdown-table-wrap.width")
local wrap = require("markdown-table-wrap.wrap")
local markdown = require("markdown-table-wrap.markdown")
local config_module = require("markdown-table-wrap.config")
local utf8 = require("markdown-table-wrap.utf8")

local M = {}
local float_namespace = vim.api.nvim_create_namespace("markdown-table-wrap-float")
local float_states = {}

local unicode = {
  top_left = "┌",
  top_join = "┬",
  top_right = "┐",
  mid_left = "├",
  mid_join = "┼",
  mid_right = "┤",
  bottom_left = "└",
  bottom_join = "┴",
  bottom_right = "┘",
  vertical = "│",
  horizontal = "─",
}

local rounded = {
  top_left = "╭",
  top_join = "┬",
  top_right = "╮",
  mid_left = "├",
  mid_join = "┼",
  mid_right = "┤",
  bottom_left = "╰",
  bottom_join = "┴",
  bottom_right = "╯",
  vertical = "│",
  horizontal = "─",
}

local ascii = {
  top_left = "+",
  top_join = "+",
  top_right = "+",
  mid_left = "+",
  mid_join = "+",
  mid_right = "+",
  bottom_left = "+",
  bottom_join = "+",
  bottom_right = "+",
  vertical = "|",
  horizontal = "-",
}

local render_border_chars = {
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

local function ensure_highlights(config)
  require("markdown-table-wrap.theme").ensure(config)
end

local function border_ranges(text)
  local ranges = {}
  local range_start = nil
  local range_end = nil

  local function flush()
    if range_start ~= nil then
      table.insert(ranges, { range_start, range_end })
      range_start = nil
      range_end = nil
    end
  end

  for ch, start_col, end_col in utf8.iter(text) do
    if render_border_chars[ch] then
      if range_start == nil then
        range_start = start_col
      end
      range_end = end_col
    else
      flush()
    end
  end
  flush()

  return ranges
end

local function append_display_chunk(chunks, text, hl_group)
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

local function append_plain_display_chunks(chunks, text, line_hl)
  for ch in utf8.iter(text) do
    append_display_chunk(chunks, ch, render_border_chars[ch] and "MarkdownTableWrapBorder" or line_hl)
  end
end

-- Build an authoritative virtual-text representation of a rendered line.
-- Reader uses this to prevent its markdown filetype (and third-party markdown
-- renderers) from parsing underscores, angle brackets, and similar characters
-- in the already-rendered table a second time. The real line remains intact for
-- search, selection, and yank.
function M.display_chunks(line_obj, line_index)
  local line = type(line_obj) == "table" and line_obj.text or line_obj or ""
  local is_header = type(line_obj) == "table" and line_obj.is_header == true
  local line_hl = (is_header or line_index == 2) and "MarkdownTableWrapHeader" or "MarkdownTableWrapInline"
  local result = {}
  local cursor = 0
  local styled_chunks = type(line_obj) == "table" and vim.deepcopy(line_obj.chunks or {}) or {}

  table.sort(styled_chunks, function(a, b)
    return a.start_col < b.start_col
  end)

  for _, styled in ipairs(styled_chunks) do
    if cursor < styled.start_col then
      append_plain_display_chunks(result, line:sub(cursor + 1, styled.start_col), line_hl)
    end

    append_display_chunk(result, line:sub(styled.start_col + 1, styled.end_col), styled.hl_group)
    cursor = styled.end_col
  end

  if cursor < #line then
    append_plain_display_chunks(result, line:sub(cursor + 1), line_hl)
  end

  return result
end

local function apply_highlights(buf, lines, config, opts)
  opts = opts or {}
  ensure_highlights(config)
  local namespace = opts.namespace or float_namespace
  local start_row = opts.start_row or 0

  if opts.clear ~= false then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end

  for row, line_obj in ipairs(lines) do
    local line = type(line_obj) == "table" and line_obj.text or line_obj
    local row_index = start_row + row - 1
    local is_header = type(line_obj) == "table" and line_obj.is_header
    local line_hl = (is_header or row == 2) and "MarkdownTableWrapHeader" or "MarkdownTableWrapInline"

    vim.api.nvim_buf_set_extmark(buf, namespace, row_index, 0, {
      end_row = row_index,
      end_col = #line,
      hl_group = line_hl,
      priority = 10,
    })

    for _, range in ipairs(border_ranges(line)) do
      vim.api.nvim_buf_set_extmark(buf, namespace, row_index, range[1], {
        end_row = row_index,
        end_col = range[2],
        hl_group = "MarkdownTableWrapBorder",
        priority = 20,
      })
    end

    for _, chunk in ipairs(type(line_obj) == "table" and line_obj.chunks or {}) do
      local mark = {
        end_row = row_index,
        end_col = chunk.end_col,
        hl_group = chunk.hl_group,
        priority = 30,
      }
      vim.api.nvim_buf_set_extmark(buf, namespace, row_index, chunk.start_col, mark)
    end
  end
end

function M.apply_highlights(buf, lines, config, opts)
  apply_highlights(buf, lines, config, opts)
end

local function text_of(line)
  return type(line) == "table" and line.text or line
end

local function hl_for_kind(kind)
  if kind == "code" then
    return "MarkdownTableWrapCode"
  elseif kind == "bold" then
    return "MarkdownTableWrapBold"
  elseif kind == "italic" then
    return "MarkdownTableWrapItalic"
  elseif kind == "strike" then
    return "MarkdownTableWrapStrike"
  elseif kind == "link" then
    return "MarkdownTableWrapLink"
  elseif kind == "wiki_link" then
    return "MarkdownTableWrapWikiLink"
  elseif kind == "image" then
    return "MarkdownTableWrapImage"
  elseif kind == "mark" then
    return "MarkdownTableWrapMark"
  end
  return nil
end

local function line_object(text, chunks, cells)
  return {
    text = text,
    chunks = chunks or {},
    cells = cells or {},
  }
end

local function border_chars(config)
  if not config.use_unicode_border then
    return ascii
  end

  if config.table_border == "single" then
    return unicode
  end

  return rounded
end

local function all_rows(table_info)
  local rows = { table_info.header }
  for _, row in ipairs(table_info.rows) do
    table.insert(rows, row)
  end
  return rows
end

local function excess_cell_count(table_info)
  local count = 0
  for _, row in ipairs(table_info.rows or {}) do
    count = count + #(row.overflow_cells or {})
  end
  return count
end

local function natural_widths(table_info, config)
  local columns = #table_info.header
  local widths = {}
  local rows = all_rows(table_info)

  for col = 1, columns do
    local max_width = 0
    for _, row in ipairs(rows) do
      max_width = math.max(max_width, width.strwidth(markdown.apply_link_icons(row[col] or "", config)))
    end
    widths[col] = max_width
  end

  return widths
end

local function table_width(col_widths, markers)
  local total = 1
  for _, col_width in ipairs(col_widths) do
    total = total + col_width + 3
  end
  markers = markers or {}
  total = total
    + (markers.left and width.strwidth(markers.value or "") or 0)
    + (markers.right and width.strwidth(markers.value or "") or 0)
  return total
end

local function sum(values)
  local total = 0
  for _, value in ipairs(values) do
    total = total + value
  end
  return total
end

local function text_area_width()
  local winid = vim.api.nvim_get_current_win()
  local info = vim.fn.getwininfo(winid)[1] or {}
  return math.max(1, vim.api.nvim_win_get_width(winid) - (info.textoff or 0))
end

local function container_prefix(table_info)
  return ((table_info or {}).container or {}).render_prefix or ""
end

local function column_rule(config, index)
  local columns = (((config or {}).wide_table or {}).columns or {})
  local rule = columns[index]
  return type(rule) == "table" and rule or {}
end

local function distribute_widths(table_info, config)
  local columns = #table_info.header
  local prefix_width = width.strwidth(container_prefix(table_info))
  local available = math.max(20, math.floor(text_area_width() * config.max_width_ratio) - prefix_width)
  local border_cost = 1 + (columns * 3)
  local content_budget = math.max(columns, available - border_cost)
  local effective_min = config.min_col_width
  if config.fit_to_window ~= false then
    effective_min = math.max(1, math.min(effective_min, math.floor(content_budget / columns)))
  else
    content_budget = math.max(columns * effective_min, content_budget)
  end
  local natural = natural_widths(table_info, config)
  local widths = {}
  local minimums = {}
  local fixed = {}

  for index = 1, columns do
    local rule = column_rule(config, index)
    local minimum = math.max(effective_min, tonumber(rule.min) or effective_min)
    local maximum = math.max(minimum, tonumber(rule.max) or config.max_col_width)
    minimums[index] = minimum
    if rule.width ~= nil then
      widths[index] = math.max(1, math.min(maximum, tonumber(rule.width) or minimum))
      fixed[index] = true
    else
      widths[index] = math.max(minimum, math.min(natural[index], maximum))
    end
  end

  local function candidate(ignore_minimum)
    local best
    for index = 1, columns do
      local rule = column_rule(config, index)
      local floor = ignore_minimum and 1 or minimums[index]
      if not fixed[index] and widths[index] > floor then
        local priority = tonumber(rule.priority) or 0
        local weight = math.max(0.01, tonumber(rule.weight) or 1)
        local score = (widths[index] - floor) / weight
        if
          not best
          or priority < best.priority
          or (priority == best.priority and score > best.score)
          or (priority == best.priority and score == best.score and index < best.index)
        then
          best = { index = index, priority = priority, score = score }
        end
      end
    end
    return best
  end

  local function shrink(ignore_minimum)
    local target = candidate(ignore_minimum)
    if not target then
      return false
    end
    widths[target.index] = widths[target.index] - 1
    return true
  end

  local overflow = false
  while sum(widths) > content_budget and shrink(false) do
    -- Keep explicit minimums whenever the requested layout permits it.
  end
  while sum(widths) > content_budget and shrink(true) do
    -- If constraints are impossible, deterministic best-effort fitting may
    -- go below a preferred minimum, but never below one display column.
  end
  if sum(widths) > content_budget then
    overflow = true
  end

  local wide = config.wide_table or {}
  if wide.allocate_extra == true and sum(widths) < content_budget then
    local spare = content_budget - sum(widths)
    while spare > 0 do
      local best
      for index = 1, columns do
        local rule = column_rule(config, index)
        local maximum = math.max(minimums[index], tonumber(rule.max) or config.max_col_width)
        if not fixed[index] and widths[index] < maximum then
          local weight = tonumber(rule.weight) or 1
          if not best or weight > best.weight or (weight == best.weight and index < best.index) then
            best = { index = index, weight = weight }
          end
        end
      end
      if not best then
        break
      end
      widths[best.index] = widths[best.index] + 1
      spare = spare - 1
    end
  end

  return widths,
    {
      available = available,
      content_budget = content_budget,
      natural_widths = natural,
      minimum_widths = minimums,
      fixed = fixed,
      overflow = overflow,
    }
end

local function border_line(chars, left, join, right, widths, markers)
  markers = markers or {}
  local parts = { markers.left and (markers.value or "…") or "", left }

  for index, col_width in ipairs(widths) do
    table.insert(parts, width.repeat_char(chars.horizontal, col_width + 2))
    table.insert(parts, index == #widths and right or join)
  end

  table.insert(parts, markers.right and (markers.value or "…") or "")
  return line_object(table.concat(parts))
end

local function row_separator_line(chars, widths, markers)
  return border_line(chars, chars.mid_left, chars.mid_join, chars.mid_right, widths, markers)
end

local function visible_columns(total, widths, config, table_info)
  local all = {}
  for index = 1, total do
    all[index] = index
  end
  local wide = config.wide_table or {}
  if wide.mode ~= "viewport" then
    return all, { left = false, right = false, value = "" }
  end

  local viewport = wide.viewport or {}
  local start = math.max(1, math.floor(tonumber(viewport.start_column) or 1))
  start = math.min(start, total)
  local count = tonumber(viewport.column_count)
  if count then
    count = math.max(1, math.floor(count))
  else
    local available = math.max(
      1,
      math.floor(text_area_width() * (config.max_width_ratio or 1)) - width.strwidth(container_prefix(table_info))
    )
    local budget = math.max(1, available - 3)
    count = 0
    local used = 0
    for index = start, total do
      local cost = widths[index] + 3
      if count > 0 and used + cost > budget then
        break
      end
      used = used + cost
      count = count + 1
    end
    count = math.max(1, count)
  end

  local finish = math.min(total, start + count - 1)
  local selected = {}
  for index = start, finish do
    table.insert(selected, index)
  end
  return selected,
    {
      left = start > 1,
      right = finish < total,
      value = type(viewport.marker) == "string" and viewport.marker ~= "" and viewport.marker or "…",
    }
end

function M.ensure_viewport(config, total_columns, active_column)
  config = config or {}
  local wide = config.wide_table or {}
  if wide.mode ~= "viewport" or type(wide.viewport) ~= "table" then
    return config
  end
  active_column = tonumber(active_column)
  if not active_column or active_column < 1 then
    return config
  end
  config = vim.deepcopy(config)
  wide = config.wide_table
  active_column = math.min(total_columns, math.floor(active_column))
  local viewport = wide.viewport
  local count = tonumber(viewport.column_count)
  if count then
    count = math.max(1, math.floor(count))
    local start = math.max(1, math.floor(tonumber(viewport.start_column) or 1))
    if active_column < start then
      start = active_column
    elseif active_column >= start + count then
      start = active_column - count + 1
    end
    viewport.start_column = math.max(1, math.min(start, math.max(1, total_columns - count + 1)))
  else
    viewport.start_column = math.max(1, math.min(active_column, total_columns))
  end
  return config
end

local function add_cell_chunks(chunks, cell_line, offset, cell_index)
  for _, span in ipairs(cell_line.spans or {}) do
    local hl = hl_for_kind(span.kind)
    if hl then
      table.insert(chunks, {
        start_col = offset + span.start_col,
        end_col = offset + span.end_col,
        hl_group = hl,
        kind = span.kind,
        url = span.url,
        cell_index = cell_index,
        source_start_col = span.source_start_col,
        source_end_col = span.source_end_col,
      })
    end
  end
end

local function render_row(row, col_widths, align, chars, config, columns, markers)
  local wrapped = {}
  local height = 1

  columns = columns or vim.tbl_map(function(_, index)
    return index
  end, col_widths)
  for visible_col, col_width in ipairs(col_widths) do
    local source_col = columns[visible_col] or visible_col
    wrapped[visible_col] = wrap.wrap_cell(markdown.apply_link_icons(row[source_col] or "", config), col_width)
    height = math.max(height, #wrapped[visible_col])
  end

  local lines = {}
  for line_index = 1, height do
    local parts = { markers and markers.left and (markers.value or "…") or "", chars.vertical }
    local chunks = {}
    local cells = {}
    local offset = (markers and markers.left and #(markers.value or "…") or 0) + #chars.vertical

    for visible_col, col_width in ipairs(col_widths) do
      local source_col = columns[visible_col] or visible_col
      local cell = wrapped[visible_col][line_index] or { text = "", spans = {} }
      local cell_text = cell.text or ""
      local padded = width.pad(cell_text, col_width, align[source_col])
      local content_offset = 1
      if align[source_col] == "right" then
        content_offset = 1 + math.max(0, col_width - width.strwidth(cell_text))
      elseif align[source_col] == "center" then
        content_offset = 1 + math.floor(math.max(0, col_width - width.strwidth(cell_text)) / 2)
      end

      table.insert(parts, " " .. padded .. " ")
      add_cell_chunks(chunks, cell, offset + content_offset, source_col)
      table.insert(cells, {
        index = source_col,
        start_col = offset,
        end_col = offset + #(" " .. padded .. " "),
        text = cell_text,
        segment_index = cell.segment_index or line_index,
        table_id = cell.table_id,
        row_index = cell.row_index,
        column_index = cell.column_index or source_col,
        source_span = cell.source_span,
        present = cell.present,
      })
      offset = offset + #(" " .. padded .. " ")
      table.insert(parts, chars.vertical)
      offset = offset + #chars.vertical
    end

    if markers and markers.right then
      table.insert(parts, markers.value or "…")
    end
    table.insert(lines, line_object(table.concat(parts), chunks, cells))
  end

  return lines
end

local function render_table(table_info, config, readonly)
  config = config or {}
  local prefix = container_prefix(table_info)
  local layout_key = table.concat({
    tostring(table_info.id or table_info.start_lnum),
    tostring(text_area_width()),
    tostring(config.max_width_ratio),
    tostring(config.min_col_width),
    tostring(config.max_col_width),
    tostring(config.fit_to_window),
    tostring(config.use_unicode_border),
    tostring(config.table_border),
    tostring(config.row_separator),
    config_module.wide_table_signature(config.wide_table),
    config_module.link_layout_signature(config.link),
    prefix,
  }, "\31")
  local cache = require("markdown-table-wrap.cache")
  local cached
  if table_info.source_bufnr then
    local stage = "layout:" .. tostring(table_info.id)
    if readonly then
      cached = cache.get_ref(table_info.source_bufnr, stage, layout_key, table_info.changedtick)
    else
      cached = cache.get(table_info.source_bufnr, stage, layout_key, table_info.changedtick)
    end
  end
  if cached then
    return cached
  end

  local chars = border_chars(config)
  local all_widths, layout = distribute_widths(table_info, config)
  local columns, markers = visible_columns(#all_widths, all_widths, config, table_info)
  local col_widths = {}
  for _, source_col in ipairs(columns) do
    table.insert(col_widths, all_widths[source_col])
  end
  local lines = {}
  local source_lnums = {}

  local function append(line, source_lnum)
    if prefix ~= "" then
      for _, chunk in ipairs(line.chunks or {}) do
        chunk.start_col = chunk.start_col + #prefix
        chunk.end_col = chunk.end_col + #prefix
      end
      for _, cell in ipairs(line.cells or {}) do
        cell.start_col = cell.start_col + #prefix
        cell.end_col = cell.end_col + #prefix
      end
      table.insert(line.chunks, 1, {
        start_col = 0,
        end_col = #prefix,
        hl_group = "Comment",
        kind = "container",
      })
      line.text = prefix .. line.text
    end
    line.table_id = table_info.id
    table.insert(lines, line)
    table.insert(source_lnums, source_lnum)
  end

  append(
    border_line(chars, chars.top_left, chars.top_join, chars.top_right, col_widths, markers),
    table_info.start_lnum
  )

  for _, line in ipairs(render_row(table_info.header, col_widths, table_info.align, chars, config, columns, markers)) do
    line.is_header = true
    append(line, table_info.start_lnum)
  end

  append(
    border_line(chars, chars.mid_left, chars.mid_join, chars.mid_right, col_widths, markers),
    table_info.separator_lnum
  )

  for row_index, row in ipairs(table_info.rows) do
    local source_lnum = table_info.separator_lnum + row_index
    for _, line in ipairs(render_row(row, col_widths, table_info.align, chars, config, columns, markers)) do
      append(line, source_lnum)
    end

    if config.row_separator and row_index < #table_info.rows then
      append(row_separator_line(chars, col_widths, markers), source_lnum)
    end
  end

  append(
    border_line(chars, chars.bottom_left, chars.bottom_join, chars.bottom_right, col_widths, markers),
    table_info.end_lnum
  )

  local excess_cells = excess_cell_count(table_info)
  local warning_text = nil
  if excess_cells > 0 then
    warning_text = string.format("⚠ +%d excess Source cell%s", excess_cells, excess_cells == 1 and "" or "s")
    append(
      line_object(warning_text, {
        { start_col = 0, end_col = #warning_text, hl_group = "DiagnosticWarn", kind = "warning" },
      }),
      table_info.end_lnum
    )
  end

  local rendered = {
    lines = vim.tbl_map(text_of, lines),
    line_objects = lines,
    source_lnums = source_lnums,
    width = width.strwidth(prefix) + math.max(table_width(col_widths, markers), width.strwidth(warning_text or "")),
    height = #lines,
    start_lnum = table_info.start_lnum,
    end_lnum = table_info.end_lnum,
    table_id = table_info.id,
    source_span = table_info.source_span,
    columns = #table_info.header,
    excess_cells = excess_cells,
    visible_columns = vim.deepcopy(columns),
    hidden_columns = { left = markers.left, right = markers.right },
    column_widths = vim.deepcopy(all_widths),
    layout = layout,
    viewport = {
      mode = (config.wide_table or {}).mode or "wrap",
      start_column = columns[1],
      end_column = columns[#columns],
      marker = markers.value,
    },
  }
  if table_info.source_bufnr then
    local stage = "layout:" .. tostring(table_info.id)
    if readonly then
      cache.set_ref(table_info.source_bufnr, stage, layout_key, table_info.changedtick, rendered)
    else
      cache.set(table_info.source_bufnr, stage, layout_key, table_info.changedtick, rendered)
    end
  end
  return rendered
end

function M.render_table(table_info, config)
  return render_table(table_info, config, false)
end

-- Internal read-only adapter for derived views. Public render_table() keeps
-- returning isolated cache values.
function M.render_table_ref(table_info, config)
  return render_table(table_info, config, true)
end

function M.open_float(rendered, config)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.lines)
  apply_highlights(buf, rendered.line_objects or rendered.lines, config)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown-table-wrap"
  vim.bo[buf].modifiable = false
  float_states[buf] = { rendered = rendered, config = config }
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      float_states[buf] = nil
    end,
  })

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local win_width = math.min(rendered.width, math.max(20, editor_width - 4))
  local win_height = math.min(rendered.height, math.max(5, editor_height - 4))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = math.max(0, math.floor((editor_height - win_height) / 2)),
    col = math.max(0, math.floor((editor_width - win_width) / 2)),
    style = "minimal",
    border = config.border,
    title = string.format(" Markdown Table Preview %dx%d ", rendered.width, rendered.height),
    title_pos = "center",
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false

  local function open_float_link()
    local plugin = require("markdown-table-wrap")
    if plugin.state.buf == buf and plugin.state.float_source_bufnr then
      require("markdown-table-wrap.actions").run("open", { bufnr = buf, winid = win })
      return
    end

    -- `open_float()` is also a public low-level renderer and can be used
    -- without plugin-owned Source state. Preserve that standalone behavior.
    local current = float_states[buf] or { rendered = rendered, config = config }
    local current_rendered = current.rendered or rendered
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_object = current_rendered.line_objects and current_rendered.line_objects[cursor[1]]
    for _, chunk in ipairs(line_object and line_object.chunks or {}) do
      if
        (chunk.kind == "link" or chunk.kind == "image")
        and chunk.url
        and chunk.url ~= ""
        and cursor[2] >= chunk.start_col
        and cursor[2] < chunk.end_col
      then
        local links = require("markdown-table-wrap.links")
        local target = links.classify(chunk.url, { kind = chunk.kind })
        links.open_target(target, { mode = "source", config = current.config or config }, {})
        return
      end
    end
    vim.notify("MarkdownTableWrap: place the cursor over a rendered link.", vim.log.levels.INFO)
  end

  local configured_mappings = (config.mappings or {}).float
  local mapping_config
  if configured_mappings == false then
    mapping_config = { enabled = false }
  else
    mapping_config = vim.tbl_deep_extend("force", {
      enabled = true,
      close = { "q", "<Esc>" },
      open_link = "gx",
      help = false,
    }, type(configured_mappings) == "table" and configured_mappings or {})
  end
  if mapping_config.enabled ~= false then
    local function map(lhs, callback, desc)
      if type(lhs) ~= "string" or lhs == "" then
        return
      end
      vim.keymap.set("n", lhs, callback, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = desc,
      })
    end

    map(mapping_config.open_link, open_float_link, "Open rendered Markdown table link")

    local close_keys = mapping_config.close
    if type(close_keys) == "string" then
      close_keys = { close_keys }
    end
    for _, lhs in ipairs(close_keys or {}) do
      map(lhs, function()
        local plugin = require("markdown-table-wrap")
        if plugin.state.buf == buf and plugin.state.float_source_bufnr then
          plugin.close_preview({ restore_origin = true })
        elseif vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end, "Close Markdown table preview")
    end

    map(mapping_config.help, function()
      require("markdown-table-wrap.actions").run("help", { bufnr = buf, winid = win })
    end, "Show Markdown table preview help")
  end

  return buf, win
end

function M.update_float(buf, rendered, config)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  local ok, err = pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, rendered.lines)
  if ok then
    ok, err = pcall(apply_highlights, buf, rendered.line_objects or rendered.lines, config)
  end
  vim.bo[buf].modifiable = modifiable
  if not ok then
    return false, err
  end
  float_states[buf] = { rendered = rendered, config = config }
  return true
end

return M
