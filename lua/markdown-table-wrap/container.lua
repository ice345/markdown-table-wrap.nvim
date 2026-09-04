local M = {}

function M.line(line)
  line = line or ""
  local cursor = 1
  local depth = 0

  while cursor <= #line do
    local marker_start = cursor
    local spaces = 0
    while spaces < 3 and line:sub(cursor, cursor) == " " do
      cursor = cursor + 1
      spaces = spaces + 1
    end
    if line:sub(cursor, cursor) ~= ">" then
      cursor = marker_start
      break
    end
    cursor = cursor + 1
    if line:sub(cursor, cursor):match("[ \t]") then
      cursor = cursor + 1
    end
    depth = depth + 1
  end

  if depth == 0 then
    return {
      kind = "source",
      depth = 0,
      content = line,
      content_start_col = 0,
      source_prefix = "",
      render_prefix = "",
      signature = "source:0",
    }
  end

  return {
    kind = "blockquote",
    depth = depth,
    content = line:sub(cursor),
    content_start_col = cursor - 1,
    source_prefix = line:sub(1, cursor - 1),
    render_prefix = string.rep("> ", depth),
    signature = "blockquote:" .. depth,
  }
end

function M.same(left, right)
  return left and right and left.signature == right.signature
end

return M
