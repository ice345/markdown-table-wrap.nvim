local M = {}

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function feed_result(result, mapping)
  if type(result) ~= "string" or result == "" then
    return true
  end

  if mapping.replace_keycodes ~= 0 then
    result = vim.api.nvim_replace_termcodes(result, true, false, true)
  end
  vim.api.nvim_feedkeys(result, mapping.noremap == 1 and "n" or "m", false)
  return true
end

function M.get(bufnr, lhs, mode)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  return vim.api.nvim_buf_call(bufnr, function()
    local mapping = vim.fn.maparg(lhs, mode or "n", false, true)
    if type(mapping) ~= "table" or next(mapping) == nil then
      return nil
    end
    return mapping
  end)
end

function M.invoke(mapping, opts)
  opts = opts or {}

  local function invoke_mapping()
    if mapping and type(mapping.callback) == "function" then
      local result = mapping.callback()
      if mapping.expr == 1 then
        return feed_result(result, mapping)
      end
      return true
    end

    if mapping and mapping.expr == 1 and type(mapping.rhs) == "string" and mapping.rhs ~= "" then
      return feed_result(vim.api.nvim_eval(mapping.rhs), mapping)
    end

    if mapping and type(mapping.rhs) == "string" and mapping.rhs ~= "" then
      local keys = vim.api.nvim_replace_termcodes(mapping.rhs, true, false, true)
      vim.api.nvim_feedkeys(keys, mapping.noremap == 1 and "n" or "m", false)
      return true
    end

    if opts.native_gx then
      local target = opts.target or vim.fn.expand("<cfile>")
      if target ~= "" and vim.ui and type(vim.ui.open) == "function" then
        vim.ui.open(target)
        return true
      end
    end

    return false
  end

  local context_bufnr = opts.context_bufnr
  local ok, result
  if context_bufnr and vim.api.nvim_buf_is_valid(context_bufnr) then
    ok, result = pcall(vim.api.nvim_buf_call, context_bufnr, function()
      if type(opts.cursor) == "table" then
        local lnum = math.max(1, math.min(tonumber(opts.cursor[1]) or 1, vim.api.nvim_buf_line_count(context_bufnr)))
        local line = vim.api.nvim_buf_get_lines(context_bufnr, lnum - 1, lnum, false)[1] or ""
        local col = math.max(0, math.min(tonumber(opts.cursor[2]) or 0, #line))
        pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
      end
      return invoke_mapping()
    end)
  else
    ok, result = pcall(invoke_mapping)
  end

  return ok and result == true
end

function M.restore(bufnr, lhs, mode, mapping)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  pcall(vim.keymap.del, mode or "n", lhs, { buffer = bufnr })
  if mapping and mapping.buffer == 1 then
    return pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.fn.mapset(mode or "n", 0, mapping)
    end)
  end
  return true
end

return M
