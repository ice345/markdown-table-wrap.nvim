local width = require("markdown-table-wrap.width")

local M = {}

local break_chars = {
  [" "] = true,
  ["\t"] = true,
  ["、"] = true,
  ["，"] = true,
  [","] = true,
  ["；"] = true,
  [";"] = true,
  ["/"] = true,
}

local code_break_chars = {
  [":"] = true,
  ["."] = true,
  ["/"] = true,
  ["_"] = true,
  ["-"] = true,
  ["="] = true,
}

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

local function span_kind_at(spans, start_col)
  for _, span in ipairs(spans or {}) do
    if start_col >= span.start_col and start_col < span.end_col then
      return span
    end
  end
  return "text"
end

local function styled_chars(cell)
  if type(cell) ~= "table" then
    cell = { text = tostring(cell or ""), spans = {} }
  end

  local result = {}
  for ch, start_col in iter_chars_with_pos(cell.text or "") do
    local span = span_kind_at(cell.spans, start_col)
    if type(span) == "table" then
      table.insert(result, { text = ch, kind = span.kind, url = span.url })
    else
      table.insert(result, { text = ch, kind = span })
    end
  end

  local coalesced = {}
  for _, item in ipairs(result) do
    local last = coalesced[#coalesced]
    if item.kind == "code" and last and last.kind == "code" then
      last.text = last.text .. item.text
    else
      table.insert(coalesced, item)
    end
  end

  return coalesced
end

local function line_from_chars(chars)
  local text = {}
  local spans = {}
  local offset = 0
  local current_kind = nil
  local current_url = nil
  local current_start = nil

  local function close_span()
    if current_kind and current_kind ~= "text" and current_start and current_start < offset then
      table.insert(spans, {
        start_col = current_start,
        end_col = offset,
        kind = current_kind,
        url = current_url,
      })
    end
    current_kind = nil
    current_url = nil
    current_start = nil
  end

  for _, item in ipairs(chars) do
    table.insert(text, item.text)

    if item.kind ~= current_kind or item.url ~= current_url then
      close_span()
      current_kind = item.kind
      current_url = item.url
      current_start = offset
    end

    offset = offset + #item.text
  end

  close_span()

  return {
    text = table.concat(text):gsub("%s+$", ""),
    spans = spans,
  }
end

local function slice_chars(chars, start_index, end_index)
  local result = {}
  for index = start_index, end_index do
    table.insert(result, chars[index])
  end
  return result
end

local function append_line(lines, chars)
  table.insert(lines, line_from_chars(chars))
end

local function expand_oversized_item(item, limit)
  if item.kind ~= "code" or width.strwidth(item.text) <= limit then
    return { item }
  end

  local pieces = {}
  for ch in iter_chars_with_pos(item.text) do
    table.insert(pieces, {
      text = ch,
      kind = item.kind,
      url = item.url,
    })
  end

  return pieces
end

local function wrap_segment(chars, limit, lines)
  local current = {}
  local last_break = nil

  for _, source_item in ipairs(chars) do
    for _, item in ipairs(expand_oversized_item(source_item, limit)) do
      while #current > 0 and width.strwidth(line_from_chars(current).text .. item.text) > limit do
        if last_break and last_break < #current then
          local break_line = line_from_chars(slice_chars(current, 1, last_break))
          if break_line.text ~= "" then
            table.insert(lines, break_line)
          end
          current = slice_chars(current, last_break + 1, #current)
        else
          append_line(lines, current)
          current = {}
        end
        last_break = nil
      end

      table.insert(current, item)
      if break_chars[item.text] or (item.kind == "code" and code_break_chars[item.text]) then
        last_break = #current
      end
    end
  end

  if #current > 0 then
    append_line(lines, current)
  end
end

function M.wrap_cell(cell, limit)
  if limit <= 0 or width.strwidth(cell) == 0 then
    return { { text = "", spans = {} } }
  end

  local lines = {}
  local segment = {}

  for _, item in ipairs(styled_chars(cell)) do
    if item.text == "\n" then
      wrap_segment(segment, limit, lines)
      segment = {}
    else
      table.insert(segment, item)
    end
  end

  wrap_segment(segment, limit, lines)

  if #lines == 0 then
    return { { text = "", spans = {} } }
  end

  return lines
end

return M
