local M = {}

local token_cache = {}
local token_cache_order = {}
local token_cache_limit = 512

local function escaped_at(text, index)
  local slashes = 0
  index = index - 1
  while index > 0 and text:sub(index, index) == "\\" do
    slashes = slashes + 1
    index = index - 1
  end
  return slashes % 2 == 1
end

local function normalize_reference(value)
  return vim.trim(tostring(value or "")):gsub("%s+", " "):lower()
end

local function references_signature(references)
  local parts = {}
  for key, value in pairs(references or {}) do
    table.insert(parts, normalize_reference(key) .. "=" .. tostring(type(value) == "table" and value.target or value))
  end
  table.sort(parts)
  return table.concat(parts, "\31")
end

local function cache_get(key)
  local value = token_cache[key]
  return value and vim.deepcopy(value) or nil
end

local function cache_put(key, value)
  if token_cache[key] == nil then
    table.insert(token_cache_order, key)
  end
  token_cache[key] = vim.deepcopy(value)
  while #token_cache_order > token_cache_limit do
    token_cache[table.remove(token_cache_order, 1)] = nil
  end
end

local function delimiter_run(text, index, marker)
  local cursor = index
  while text:sub(cursor, cursor) == marker do
    cursor = cursor + 1
  end
  return cursor - index
end

local function find_closing_run(text, start_index, marker, length)
  local cursor = start_index
  while cursor <= #text do
    local found = text:find(marker, cursor, true)
    if not found then
      return nil
    end
    if not escaped_at(text, found) and delimiter_run(text, found, marker) == length then
      return found, found + length - 1
    end
    cursor = found + math.max(1, delimiter_run(text, found, marker))
  end
  return nil
end

local function find_balanced(text, open_index, open_char, close_char)
  local depth = 0
  local cursor = open_index
  while cursor <= #text do
    local ch = text:sub(cursor, cursor)
    if ch == "`" and not escaped_at(text, cursor) then
      local length = delimiter_run(text, cursor, "`")
      local close = find_closing_run(text, cursor + length, "`", length)
      if close then
        cursor = close + length
        goto continue
      end
    end
    if not escaped_at(text, cursor) then
      if ch == open_char then
        depth = depth + 1
      elseif ch == close_char then
        depth = depth - 1
        if depth == 0 then
          return cursor
        end
      end
    end
    cursor = cursor + 1
    ::continue::
  end
  return nil
end

local function destination(text, open_index)
  local close_index = find_balanced(text, open_index, "(", ")")
  if not close_index then
    return nil
  end
  local value = vim.trim(text:sub(open_index + 1, close_index - 1))
  local angle = value:match("^<([^>]*)>")
  if angle then
    value = angle
  else
    value = value:match("^(%S+)%s+[\"'(].-$") or value
  end
  return close_index, value:gsub("\\([()])", "%1")
end

local function text_of(nodes)
  local result = {}
  for _, node in ipairs(nodes or {}) do
    table.insert(result, node.text or "")
  end
  return table.concat(result)
end

local parse_nodes

local function delimited_node(text, index, marker, kind, references, depth)
  local close_start = text:find(marker, index + #marker, true)
  while close_start and escaped_at(text, close_start) do
    close_start = text:find(marker, close_start + #marker, true)
  end
  if not close_start then
    return nil
  end

  if marker == "_" then
    local previous = text:sub(index - 1, index - 1)
    local following = text:sub(close_start + 1, close_start + 1)
    if previous:match("[%w]") or following:match("[%w]") then
      return nil
    end
  end

  local children = parse_nodes(text, index + #marker, close_start - 1, references, depth + 1)
  return {
    kind = kind,
    text = text_of(children),
    children = children,
    source_start_col = index - 1,
    source_end_col = close_start + #marker - 1,
  },
    close_start + #marker
end

local function link_node(text, index, image, references, depth)
  local label_open = image and index + 1 or index
  if text:sub(label_open, label_open) ~= "[" then
    return nil
  end
  local label_close = find_balanced(text, label_open, "[", "]")
  if not label_close then
    return nil
  end

  local after = label_close + 1
  local target
  local finish
  local reference
  local target_kind
  if text:sub(after, after) == "(" then
    finish, target = destination(text, after)
    target_kind = "inline"
  elseif text:sub(after, after) == "[" then
    local ref_close = find_balanced(text, after, "[", "]")
    if ref_close then
      reference = text:sub(after + 1, ref_close - 1)
      if reference == "" then
        reference = text:sub(label_open + 1, label_close - 1)
      end
      local definition = references[normalize_reference(reference)]
      target = type(definition) == "table" and definition.target or definition
      finish = target and ref_close or nil
      target_kind = "reference"
    end
  else
    reference = text:sub(label_open + 1, label_close - 1)
    local definition = references[normalize_reference(reference)]
    target = type(definition) == "table" and definition.target or definition
    finish = target and label_close or nil
    target_kind = "reference"
  end

  if not finish or not target or target == "" then
    return nil
  end

  local children = parse_nodes(text, label_open + 1, label_close - 1, references, depth + 1)
  return {
    kind = image and "image" or "link",
    text = text_of(children),
    children = children,
    target = target,
    url = target,
    target_kind = target_kind,
    reference = reference,
    source_start_col = index - 1,
    source_end_col = finish,
  },
    finish + 1
end

local function reversed_link_node(text, index)
  local label_close = find_balanced(text, index, "(", ")")
  if not label_close or text:sub(label_close + 1, label_close + 1) ~= "[" then
    return nil
  end
  local target_close = find_balanced(text, label_close + 1, "[", "]")
  if not target_close then
    return nil
  end
  local target = text:sub(label_close + 2, target_close - 1)
  if target == "" then
    return nil
  end
  local label = text:sub(index + 1, label_close - 1)
  return {
    kind = "link",
    text = label,
    target = target,
    url = target,
    target_kind = "legacy",
    source_start_col = index - 1,
    source_end_col = target_close,
  },
    target_close + 1
end

local function push_plain(nodes, text, start_index, end_index)
  if end_index < start_index then
    return
  end
  local value = text:sub(start_index, end_index)
  local last = nodes[#nodes]
  if last and last.kind == "text" and last.source_end_col == start_index - 1 then
    last.text = last.text .. value
    last.source_end_col = end_index
  else
    table.insert(nodes, {
      kind = "text",
      text = value,
      source_start_col = start_index - 1,
      source_end_col = end_index,
    })
  end
end

parse_nodes = function(text, first, last, references, depth)
  local nodes = {}
  local index = first
  references = references or {}
  depth = depth or 0
  if depth > 32 then
    push_plain(nodes, text, first, last)
    return nodes
  end

  while index <= last do
    local node
    local next_index
    local ch = text:sub(index, index)
    local break_match = ch == "<" and text:sub(index, last):match("^<[Bb][Rr]%s*/?>") or nil

    if ch == "\\" and index < last and text:sub(index + 1, index + 1):match("[%p]") then
      node = {
        kind = "text",
        text = text:sub(index + 1, index + 1),
        source_start_col = index - 1,
        source_end_col = index + 1,
      }
      next_index = index + 2
    elseif ch == "`" and not escaped_at(text, index) then
      local length = delimiter_run(text, index, "`")
      local close_start, close_end = find_closing_run(text, index + length, "`", length)
      if close_start and close_end <= last then
        local value = text:sub(index + length, close_start - 1):gsub("[\r\n]+", " ")
        if value:sub(1, 1) == " " and value:sub(-1) == " " and value:match("^ +$") == nil then
          value = value:sub(2, -2)
        end
        node = {
          kind = "code",
          text = value,
          delimiter_length = length,
          source_start_col = index - 1,
          source_end_col = close_end,
        }
        next_index = close_end + 1
      end
    elseif text:sub(index, index + 1) == "[[" then
      local close = text:find("]]", index + 2, true)
      if close and close + 1 <= last then
        local value = text:sub(index + 2, close - 1)
        local target, label = value:match("^([^|]+)|(.+)$")
        target = target or value
        label = label or value
        node = {
          kind = "wiki_link",
          text = label,
          target = target,
          url = target,
          source_start_col = index - 1,
          source_end_col = close + 1,
        }
        next_index = close + 2
      end
    elseif break_match then
      node = {
        kind = "break",
        text = "\n",
        source_start_col = index - 1,
        source_end_col = index + #break_match - 1,
      }
      next_index = index + #break_match
    elseif ch == "<" then
      local close = text:find(">", index + 1, true)
      if close and close <= last then
        local value = text:sub(index + 1, close - 1)
        if value:match("^[A-Za-z][A-Za-z0-9+.-]+:[^ <>]+$") then
          node = {
            kind = "link",
            text = value,
            target = value,
            url = value,
            target_kind = "autolink",
            source_start_col = index - 1,
            source_end_col = close,
          }
          next_index = close + 1
        elseif value:match("^[^ <>@]+@[^ <>@]+%.[^ <>@]+$") then
          node = {
            kind = "link",
            text = value,
            target = "mailto:" .. value,
            url = "mailto:" .. value,
            target_kind = "autolink",
            source_start_col = index - 1,
            source_end_col = close,
          }
          next_index = close + 1
        end
      end
    elseif text:sub(index, index + 1) == "![" then
      node, next_index = link_node(text, index, true, references, depth)
    elseif ch == "[" then
      node, next_index = link_node(text, index, false, references, depth)
    elseif ch == "(" then
      node, next_index = reversed_link_node(text, index)
    end

    if not node then
      local specs = {
        { "**", "bold" },
        { "__", "bold" },
        { "~~", "strike" },
        { "==", "mark" },
        { "*", "italic" },
        { "_", "italic" },
      }
      for _, spec in ipairs(specs) do
        if text:sub(index, index + #spec[1] - 1) == spec[1] and not escaped_at(text, index) then
          node, next_index = delimited_node(text, index, spec[1], spec[2], references, depth)
          if node then
            break
          end
        end
      end
    end

    if node and next_index and next_index - 1 <= last then
      table.insert(nodes, node)
      index = next_index
    else
      push_plain(nodes, text, index, index)
      index = index + 1
    end
  end
  return nodes
end

local function build_result(text, references)
  local nodes = parse_nodes(text, 1, #text, references, 0)
  local display = {}
  local tokens = {}
  local spans = {}
  local offset = 0

  local function record(node, render_start, inside_style, inside_target)
    local token = vim.deepcopy(node)
    token.render_start_col = render_start
    token.render_end_col = render_start + #(node.text or "")
    token.children = {}
    table.insert(tokens, token)

    local is_target = node.kind == "link" or node.kind == "image" or node.kind == "wiki_link"
    token.nested_target = is_target and inside_target or nil
    if
      node.kind ~= "text"
      and node.kind ~= "break"
      and ((is_target and not inside_target) or (not is_target and not inside_style))
      and token.render_end_col > render_start
    then
      table.insert(spans, {
        start_col = render_start,
        end_col = token.render_end_col,
        source_start_col = node.source_start_col,
        source_end_col = node.source_end_col,
        kind = node.kind,
        url = node.target,
        target = node.target,
        target_kind = node.target_kind,
        reference = node.reference,
      })
    end

    local child_offset = render_start
    for _, child in ipairs(node.children or {}) do
      local child_token = record(
        child,
        child_offset,
        inside_style or (node.kind ~= "text" and node.kind ~= "break"),
        inside_target or is_target
      )
      table.insert(token.children, child_token)
      child_offset = child_offset + #(child.text or "")
    end
    return token
  end

  for _, node in ipairs(nodes) do
    table.insert(display, node.text)
    record(node, offset, false, false)
    offset = offset + #node.text
  end

  return { raw = text, text = table.concat(display), spans = spans, tokens = tokens }
end

function M.parse_inline(text, opts)
  text = tostring(text or "")
  opts = type(opts) == "table" and opts or {}
  local references = opts.references or {}
  local key = text .. "\30" .. references_signature(references)
  local cached = opts.cache == false and nil or cache_get(key)
  if cached then
    return cached
  end
  local result = build_result(text, references)
  if opts.cache ~= false then
    cache_put(key, result)
  end
  return result
end

function M.inline_to_text(text, opts)
  return M.parse_inline(text, opts).text
end

function M.extract_links(value, opts)
  opts = type(opts) == "table" and opts or {}
  local parsed_input = type(value) == "table" and value.tokens ~= nil
  local parsed = parsed_input and value or M.parse_inline(value, opts)
  local links = {}
  for _, token in ipairs(parsed.tokens or {}) do
    if
      (token.kind == "link" or token.kind == "image" or token.kind == "wiki_link")
      and token.target
      and not token.nested_target
    then
      table.insert(links, {
        start_col = parsed_input and opts.coordinates ~= "source" and token.render_start_col or token.source_start_col,
        end_col = parsed_input and opts.coordinates ~= "source" and token.render_end_col or token.source_end_col,
        source_start_col = token.source_start_col,
        source_end_col = token.source_end_col,
        text = token.text,
        url = token.target,
        target = token.target,
        kind = token.kind,
      })
    end
  end
  table.sort(links, function(a, b)
    return a.start_col < b.start_col
  end)
  return links
end

local function link_icon(span, config)
  local link = (config or {}).link or {}
  local url = span.url or span.target or ""
  if span.kind == "wiki_link" then
    return type(link.wiki) == "table" and (link.wiki.icon or "") or ""
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
    local icon = (span.kind == "link" or span.kind == "wiki_link" or span.kind == "image") and link_icon(span, config)
      or ""
    local rendered = icon .. raw
    table.insert(out, rendered)
    local copy = vim.deepcopy(span)
    copy.start_col = offset
    copy.end_col = offset + #rendered
    table.insert(out_spans, copy)
    offset = offset + #rendered
    cursor = span.end_col
  end
  if cursor < #text then
    table.insert(out, text:sub(cursor + 1))
  end
  local result = vim.deepcopy(cell)
  result.text = table.concat(out)
  result.spans = out_spans
  return result
end

function M.clear_cache()
  token_cache = {}
  token_cache_order = {}
end

function M.cache_size()
  return #token_cache_order
end

return M
