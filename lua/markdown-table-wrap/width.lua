local M = {}

function M.strwidth(text)
  if type(text) == "table" then
    text = text.text or ""
  end
  return vim.api.nvim_strwidth(text or "")
end

function M.repeat_char(char, count)
  if count <= 0 then
    return ""
  end

  return string.rep(char, count)
end

function M.pad_right(text, target_width)
  text = text or ""
  local missing = target_width - M.strwidth(text)
  return text .. M.repeat_char(" ", missing)
end

function M.pad_left(text, target_width)
  text = text or ""
  local missing = target_width - M.strwidth(text)
  return M.repeat_char(" ", missing) .. text
end

function M.pad_center(text, target_width)
  text = text or ""
  local missing = target_width - M.strwidth(text)
  local left = math.floor(missing / 2)
  local right = missing - left
  return M.repeat_char(" ", left) .. text .. M.repeat_char(" ", right)
end

function M.pad(text, target_width, align)
  if align == "right" then
    return M.pad_left(text, target_width)
  elseif align == "center" then
    return M.pad_center(text, target_width)
  end

  return M.pad_right(text, target_width)
end

function M.max_cell_width(cells)
  local max_width = 0

  for _, cell in ipairs(cells) do
    max_width = math.max(max_width, M.strwidth(cell))
  end

  return max_width
end

return M
