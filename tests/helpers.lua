local M = {
  failures = {},
  count = 0,
}

function M.fail(name, message)
  table.insert(M.failures, string.format("%s: %s", name, message))
end

function M.assert_eq(name, actual, expected)
  if actual ~= expected then
    M.fail(name, string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

function M.assert_deep_eq(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    M.fail(name, string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

function M.assert_true(name, value)
  if not value then
    M.fail(name, "expected truthy value")
  end
end

function M.assert_false(name, value)
  if value then
    M.fail(name, "expected falsy value")
  end
end

function M.test(name, fn)
  M.count = M.count + 1
  local ok, err = pcall(fn)
  if not ok then
    M.fail(name, err)
  end
end

function M.with_buffer(lines, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ok, err = pcall(fn, buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if not ok then
    error(err, 0)
  end
end

function M.finish()
  if #M.failures > 0 then
    for _, failure in ipairs(M.failures) do
      print("FAIL " .. failure)
    end
    vim.cmd("cquit")
  end

  print(string.format("PASS %d tests", M.count))
end

return M
