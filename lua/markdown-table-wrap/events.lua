local M = {}

local function safe_data(data)
  local result = {}
  for key, value in pairs(data or {}) do
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
      result[key] = value
    end
  end
  return result
end

function M.emit(pattern, data)
  local opts = {
    pattern = pattern,
    modeline = false,
    data = safe_data(data),
  }
  local ok = pcall(vim.api.nvim_exec_autocmds, "User", opts)
  if not ok then
    opts.data = nil
    pcall(vim.api.nvim_exec_autocmds, "User", opts)
  end
end

return M
