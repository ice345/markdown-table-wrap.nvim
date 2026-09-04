local container = require("markdown-table-wrap.container")

local M = {}

function M.parts(line)
  local indent, marker, tail = (line or ""):match("^( *)([`~]+)(.*)$")
  if not marker or #indent > 3 or #marker < 3 then
    return nil
  end
  local char = marker:sub(1, 1)
  if marker:match("^" .. char .. "+$") == nil then
    return nil
  end
  return char, #marker, tail
end

function M.opener(line)
  local char, length, tail = M.parts(line)
  if not char or (char == "`" and tail:find("`", 1, true)) then
    return nil
  end
  return char, length
end

function M.is_closer(line, fence_char, fence_length)
  local char, length, tail = M.parts(line)
  return char == fence_char and length >= fence_length and tail:match("^[ \t]*$") ~= nil
end

function M.mask(lines)
  local result = {}
  local active = nil

  for lnum, line in ipairs(lines or {}) do
    local current = container.line(line)
    if active and active.container_signature ~= "source:0" and current.signature ~= active.container_signature then
      active = nil
    end
    if active then
      result[lnum] = true
      local content = active.container_signature == "source:0" and line or current.content
      if M.is_closer(content, active.char, active.length) then
        active = nil
      end
    else
      local char, length = M.opener(current.content)
      if char then
        result[lnum] = true
        active = { char = char, length = length, container_signature = current.signature }
      end
    end
  end

  return result
end

return M
