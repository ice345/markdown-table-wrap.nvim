local width = require("markdown-table-wrap.width")
local wrap = require("markdown-table-wrap.wrap")
local markdown = require("markdown-table-wrap.markdown")

local M = {}
local float_namespace = vim.api.nvim_create_namespace("markdown-table-wrap-float")

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
  require("markdown-table-wrap.theme").apply(config)
end

local function iter_chars_with_pos(text)
  local index = 1
  return function()
    if index > #text then
      return nil
    end

    local start_col, end_col, ch = text:find("([%z\1-\127\194-\244][\128-\191]*)", index)
    if not start_col then
      return nil
    end

    index = end_col + 1
    return ch, start_col - 1, end_col
  end
end

local function apply_float_highlights(buf, lines, config)
  ensure_highlights(config)

  for row, line_obj in ipairs(lines) do
    local line = type(line_obj) == "table" and line_obj.text or line_obj
    local row_index = row - 1
    local line_hl = row == 2 and "MarkdownTableWrapHeader" or "MarkdownTableWrapInline"

    vim.api.nvim_buf_set_extmark(buf, float_namespace, row_index, 0, {
      end_row = row_index,
      end_col = #line,
      hl_group = line_hl,
      priority = 10,
    })

    for ch, start_col, end_col in iter_chars_with_pos(line) do
      if render_border_chars[ch] then
        vim.api.nvim_buf_set_extmark(buf, float_namespace, row_index, start_col, {
          end_row = row_index,
          end_col = end_col,
          hl_group = "MarkdownTableWrapBorder",
          priority = 20,
        })
      end
    end

    for _, chunk in ipairs(type(line_obj) == "table" and line_obj.chunks or {}) do
      vim.api.nvim_buf_set_extmark(buf, float_namespace, row_index, chunk.start_col, {
        end_row = row_index,
        end_col = chunk.end_col,
        hl_group = chunk.hl_group,
        priority = 30,
      })
    end
  end
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

local function line_object(text, chunks)
  return {
    text = text,
    chunks = chunks or {},
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

local function natural_widths(table_info)
  local columns = #table_info.header
  local widths = {}
  local rows = all_rows(table_info)

  for col = 1, columns do
    local max_width = 0
    for _, row in ipairs(rows) do
      max_width = math.max(max_width, width.strwidth(row[col] or ""))
    end
    widths[col] = max_width
  end

  return widths
end

local function table_width(col_widths)
  local total = 1
  for _, col_width in ipairs(col_widths) do
    total = total + col_width + 3
  end
  return total
end

local function sum(values)
  local total = 0
  for _, value in ipairs(values) do
    total = total + value
  end
  return total
end

local function distribute_widths(table_info, config)
  local columns = #table_info.header
  local available = math.max(20, math.floor(vim.api.nvim_win_get_width(0) * config.max_width_ratio))
  local border_cost = 1 + (columns * 3)
  local content_budget = math.max(columns * config.min_col_width, available - border_cost)
  local widths = natural_widths(table_info)

  for index = 1, columns do
    widths[index] = math.max(config.min_col_width, math.min(widths[index], config.max_col_width))
  end

  while sum(widths) > content_budget do
    local widest_index = 1
    for index = 2, columns do
      if widths[index] > widths[widest_index] then
        widest_index = index
      end
    end

    if widths[widest_index] <= config.min_col_width then
      break
    end

    widths[widest_index] = widths[widest_index] - 1
  end

  return widths
end

local function border_line(chars, left, join, right, widths)
  local parts = { left }

  for index, col_width in ipairs(widths) do
    table.insert(parts, width.repeat_char(chars.horizontal, col_width + 2))
    table.insert(parts, index == #widths and right or join)
  end

  return line_object(table.concat(parts))
end

local function row_separator_line(chars, widths)
  return border_line(chars, chars.mid_left, chars.mid_join, chars.mid_right, widths)
end

local function add_cell_chunks(chunks, cell_line, offset)
  for _, span in ipairs(cell_line.spans or {}) do
    local hl = hl_for_kind(span.kind)
    if hl then
      table.insert(chunks, {
        start_col = offset + span.start_col,
        end_col = offset + span.end_col,
        hl_group = hl,
        kind = span.kind,
        url = span.url,
      })
    end
  end
end

local function render_row(row, col_widths, align, chars, config)
  local wrapped = {}
  local height = 1

  for col, col_width in ipairs(col_widths) do
    wrapped[col] = wrap.wrap_cell(markdown.apply_link_icons(row[col] or "", config), col_width)
    height = math.max(height, #wrapped[col])
  end

  local lines = {}
  for line_index = 1, height do
    local parts = { chars.vertical }
    local chunks = {}
    local offset = #chars.vertical

    for col, col_width in ipairs(col_widths) do
      local cell = wrapped[col][line_index] or { text = "", spans = {} }
      local cell_text = cell.text or ""
      local padded = width.pad(cell_text, col_width, align[col])
      local content_offset = 1
      if align[col] == "right" then
        content_offset = 1 + math.max(0, col_width - width.strwidth(cell_text))
      elseif align[col] == "center" then
        content_offset = 1 + math.floor(math.max(0, col_width - width.strwidth(cell_text)) / 2)
      end

      table.insert(parts, " " .. padded .. " ")
      add_cell_chunks(chunks, cell, offset + content_offset)
      offset = offset + #(" " .. padded .. " ")
      table.insert(parts, chars.vertical)
      offset = offset + #chars.vertical
    end

    table.insert(lines, line_object(table.concat(parts), chunks))
  end

  return lines
end

function M.render_table(table_info, config)
  local chars = border_chars(config)
  local col_widths = distribute_widths(table_info, config)
  local lines = {}

  table.insert(lines, border_line(chars, chars.top_left, chars.top_join, chars.top_right, col_widths))

  for _, line in ipairs(render_row(table_info.header, col_widths, table_info.align, chars, config)) do
    table.insert(lines, line)
  end

  table.insert(lines, border_line(chars, chars.mid_left, chars.mid_join, chars.mid_right, col_widths))

  for row_index, row in ipairs(table_info.rows) do
    for _, line in ipairs(render_row(row, col_widths, table_info.align, chars, config)) do
      table.insert(lines, line)
    end

    if config.row_separator and row_index < #table_info.rows then
      table.insert(lines, row_separator_line(chars, col_widths))
    end
  end

  table.insert(lines, border_line(chars, chars.bottom_left, chars.bottom_join, chars.bottom_right, col_widths))

  return {
    lines = vim.tbl_map(text_of, lines),
    line_objects = lines,
    width = table_width(col_widths),
    height = #lines,
    start_lnum = table_info.start_lnum,
    end_lnum = table_info.end_lnum,
  }
end

function M.open_float(rendered, config)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.lines)
  apply_float_highlights(buf, rendered.line_objects or rendered.lines, config)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown-table-wrap"
  vim.bo[buf].modifiable = false

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
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_object = rendered.line_objects and rendered.line_objects[cursor[1]]
    local col = cursor[2]
    local url = nil

    for _, chunk in ipairs(line_object and line_object.chunks or {}) do
      if (chunk.kind == "link" or chunk.kind == "image") and chunk.url and chunk.url ~= "" then
        if col >= chunk.start_col and col < chunk.end_col then
          url = chunk.url
          break
        end
      end
    end

    if not url then
      vim.notify("MarkdownTableWrap: place the cursor over a rendered link.", vim.log.levels.INFO)
      return
    end

    vim.ui.open(url)
  end

  vim.keymap.set("n", "gx", open_float_link, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = "Open rendered Markdown table link",
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "Close Markdown table preview" })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true, desc = "Close Markdown table preview" })

  return buf, win
end

return M
