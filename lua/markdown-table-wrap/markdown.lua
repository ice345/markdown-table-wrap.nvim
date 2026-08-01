local M = {}

local function push_text(parts, text, kind, meta)
  if text == "" then
    return
  end

  table.insert(parts, { text = text, kind = kind or "text", meta = meta or {} })
end

local function escaped_at(text, index)
  local slashes = 0
  index = index - 1

  while index > 0 and text:sub(index, index) == "\\" do
    slashes = slashes + 1
    index = index - 1
  end

  return slashes % 2 == 1
end

-- Link labels can contain inline code, for example
-- ``[`overview`](curriculum/week-01/overview.md)``. Markdown conceal rules
-- hide those backticks in the editor, so retaining them in the display text
-- would make the rendered border appear to drift left by two character widths.
-- Remove only matched, unescaped code delimiters. Unmatched or escaped
-- backticks stay visible and continue to behave as ordinary label text.
local function strip_code_delimiters(value)
  local result = {}
  local cursor = 1

  while cursor <= #value do
    local start_col, end_col, ticks = value:find("(`+)", cursor)
    if not start_col then
      table.insert(result, value:sub(cursor))
      break
    end

    if escaped_at(value, start_col) then
      table.insert(result, value:sub(cursor, end_col))
      cursor = end_col + 1
      goto continue
    end

    local close_start = nil
    local close_end = nil
    local search = end_col + 1
    while search <= #value do
      local candidate_start, candidate_end, candidate = value:find("(`+)", search)
      if not candidate_start then
        break
      end

      if not escaped_at(value, candidate_start) and #candidate == #ticks then
        close_start = candidate_start
        close_end = candidate_end
        break
      end
      search = candidate_end + 1
    end

    if not close_start then
      table.insert(result, value:sub(cursor))
      break
    end

    table.insert(result, value:sub(cursor, start_col - 1))
    table.insert(result, value:sub(end_col + 1, close_start - 1))
    cursor = close_end + 1

    ::continue::
  end

  return table.concat(result)
end

local function earliest_match(text, index)
  local candidates = {}

  local specs = {
    { kind = "code", pattern = "``([^`]*)``" },
    { kind = "code", pattern = "`([^`]*)`" },
    { kind = "bold", pattern = "%*%*([^%*]+)%*%*" },
    { kind = "bold", pattern = "__([^_]+)__" },
    { kind = "italic", pattern = "%*([^%*]+)%*" },
    { kind = "italic", pattern = "_([^_]+)_" },
    { kind = "strike", pattern = "~~([^~]+)~~" },
    { kind = "mark", pattern = "==([^=]+)==" },
    { kind = "wiki_link", pattern = "%[%[([^%]]*)%]%]" },
    { kind = "image", pattern = "!%[([^%]]*)%]%(([^%)]*)%)" },
    { kind = "link", pattern = "%[([^%]]*)%]%(([^%)]*)%)" },
    { kind = "link", pattern = "%(([^%)]*)%)%[([^%]]*)%]" },
    { kind = "break", pattern = "<br%s*/?>" },
    { kind = "break", pattern = "<BR%s*/?>" },
  }

  for _, spec in ipairs(specs) do
    local captures = { text:find(spec.pattern, index) }
    local start_col, end_col = captures[1], captures[2]
    if start_col then
      local first = captures[3] or ""
      local second = captures[4] or ""
      local value = first
      local url = second

      if spec.kind == "break" then
        value = "\n"
      elseif spec.kind == "link" and spec.pattern == "%(([^%)]*)%)%[([^%]]*)%]" then
        value = first
        url = second
      end

      if spec.kind == "link" or spec.kind == "image" then
        value = strip_code_delimiters(value)
      end

      table.insert(candidates, {
        start_col = start_col,
        end_col = end_col,
        value = value,
        url = url,
        kind = spec.kind == "break" and "text" or spec.kind,
      })
    end
  end

  table.sort(candidates, function(a, b)
    if a.start_col == b.start_col then
      return a.end_col > b.end_col
    end
    return a.start_col < b.start_col
  end)

  return candidates[1]
end

function M.parse_inline(text)
  text = tostring(text or "")

  local parts = {}
  local index = 1

  while index <= #text do
    local match = earliest_match(text, index)
    if not match then
      push_text(parts, text:sub(index), "text")
      break
    end

    if match.start_col > index then
      push_text(parts, text:sub(index, match.start_col - 1), "text")
    end

    push_text(parts, match.value, match.kind, { url = match.url })
    index = match.end_col + 1
  end

  local display = {}
  local spans = {}
  local offset = 0

  for _, part in ipairs(parts) do
    table.insert(display, part.text)

    if part.kind ~= "text" and part.text ~= "" then
      table.insert(spans, {
        start_col = offset,
        end_col = offset + #part.text,
        kind = part.kind,
        url = part.meta.url,
      })
    end

    offset = offset + #part.text
  end

  return {
    text = table.concat(display),
    spans = spans,
  }
end

function M.inline_to_text(text)
  return M.parse_inline(text).text
end

function M.extract_links(text)
  if type(text) == "table" and text.spans then
    local parsed_links = {}
    for _, span in ipairs(text.spans) do
      if (span.kind == "link" or span.kind == "image") and span.url and span.url ~= "" then
        table.insert(parsed_links, {
          start_col = span.start_col,
          end_col = span.end_col,
          text = text.text:sub(span.start_col + 1, span.end_col),
          url = span.url,
          kind = span.kind,
        })
      end
    end
    return parsed_links
  end

  text = tostring(text or "")
  local links = {}

  local patterns = {
    { pattern = "!%[([^%]]*)%]%(([^%)]*)%)", text_index = 1, url_index = 2, kind = "image" },
    { pattern = "%[([^%]]*)%]%(([^%)]*)%)", text_index = 1, url_index = 2, kind = "link" },
    { pattern = "%(([^%)]*)%)%[([^%]]*)%]", text_index = 1, url_index = 2, kind = "link" },
  }

  for _, spec in ipairs(patterns) do
    local index = 1
    while index <= #text do
      local captures = { text:find(spec.pattern, index) }
      local start_col, end_col = captures[1], captures[2]
      if not start_col then
        break
      end

      local is_image_duplicate = spec.kind == "link" and start_col > 1 and text:sub(start_col - 1, start_col - 1) == "!"
      if not is_image_duplicate then
        table.insert(links, {
          start_col = start_col - 1,
          end_col = end_col,
          text = captures[2 + spec.text_index] or "",
          url = captures[2 + spec.url_index] or "",
          kind = spec.kind,
        })
      end
      index = end_col + 1
    end
  end

  table.sort(links, function(a, b)
    return a.start_col < b.start_col
  end)

  return links
end

local function link_icon(span, config)
  local link = (config or {}).link or {}
  local url = span.url or ""

  if span.kind == "wiki_link" then
    local wiki = link.wiki
    if type(wiki) == "table" then
      return wiki.icon or ""
    end
    return ""
  elseif span.kind == "image" then
    return type(link.image) == "string" and link.image or ""
  end

  for _, item in pairs(link.custom or {}) do
    if item.pattern and url:lower():find(tostring(item.pattern):lower(), 1, true) then
      return item.icon or ""
    end
  end

  return link.icon or ""
end

function M.apply_link_icons(cell, config)
  if type(cell) ~= "table" or not cell.spans or #cell.spans == 0 then
    return cell
  end

  local text = cell.text or ""
  local spans = vim.deepcopy(cell.spans)
  table.sort(spans, function(a, b)
    return a.start_col < b.start_col
  end)

  local out = {}
  local out_spans = {}
  local cursor = 0
  local offset = 0

  for _, span in ipairs(spans) do
    if cursor < span.start_col then
      local plain = text:sub(cursor + 1, span.start_col)
      table.insert(out, plain)
      offset = offset + #plain
    end

    local raw = text:sub(span.start_col + 1, span.end_col)
    local icon = ""
    if span.kind == "link" or span.kind == "wiki_link" or span.kind == "image" then
      icon = link_icon(span, config)
    end

    local rendered = icon .. raw
    table.insert(out, rendered)
    table.insert(out_spans, {
      start_col = offset,
      end_col = offset + #rendered,
      kind = span.kind,
      url = span.url,
    })
    offset = offset + #rendered
    cursor = span.end_col
  end

  if cursor < #text then
    table.insert(out, text:sub(cursor + 1))
  end

  return {
    text = table.concat(out),
    spans = out_spans,
  }
end

return M
