local M = {}

local function is_continuation(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

local function sequence_length(text, index)
  local lead = text:byte(index)
  if not lead or lead < 0x80 then
    return 1
  end

  local length
  if lead >= 0xC2 and lead <= 0xDF then
    length = 2
  elseif lead >= 0xE0 and lead <= 0xEF then
    length = 3
  elseif lead >= 0xF0 and lead <= 0xF4 then
    length = 4
  else
    return 1
  end

  if index + length - 1 > #text then
    return 1
  end
  for offset = 1, length - 1 do
    if not is_continuation(text:byte(index + offset)) then
      return 1
    end
  end
  return length
end

-- The scanner is deliberately tolerant: an invalid byte is returned as a
-- one-byte character so later structural ASCII is never skipped.
function M.next(text, index)
  index = math.max(1, tonumber(index) or 1)
  if index > #text then
    return nil
  end
  local end_col = index + sequence_length(text, index) - 1
  return text:sub(index, end_col), index, end_col
end

-- Iteration columns follow Neovim's 0-based, end-exclusive byte convention.
function M.iter(text)
  local index = 1
  return function()
    local ch, start_col, end_col = M.next(text, index)
    if not ch then
      return nil
    end
    index = end_col + 1
    return ch, start_col - 1, end_col
  end
end

return M
