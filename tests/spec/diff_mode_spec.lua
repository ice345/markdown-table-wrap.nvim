local h = require("tests.helpers")

local left_lines = {
  "| Name  | Value |",
  "| ----- | ----- |",
  "| Alpha | 1     |",
}

local right_lines = {
  "| Name  | Value |",
  "| ----- | ----- |",
  "| Alpha | 2     |",
}

local function delete_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function wait_for(predicate, timeout)
  vim.wait(timeout or 300, predicate, 10)
end

h.test("Reader does not open in a window that is already in diff mode", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local left_win = vim.api.nvim_get_current_win()
  local left = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(left_win, left)

  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  local right = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)
  wait_for(function()
    return vim.wo[left_win].diff and vim.wo[right_win].diff
  end)

  plugin.schedule_refresh({ bufnr = left, winid = left_win, silent = true, immediate = true })
  plugin.schedule_refresh({ bufnr = right, winid = right_win, silent = true, immediate = true })
  wait_for(function()
    return false
  end, 50)

  h.assert_true("left window keeps diff mode", vim.wo[left_win].diff)
  h.assert_true("right window keeps diff mode", vim.wo[right_win].diff)
  h.assert_false("left window is not wrapped into Reader", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
  h.assert_false("right window is not wrapped into Reader", reader.is_reader(vim.api.nvim_win_get_buf(right_win)))

  vim.cmd("diffoff!")
  vim.api.nvim_win_close(right_win, true)
  delete_buffer(left)
  delete_buffer(right)
  plugin.state.paused_buffers = {}
end)

h.test("diffthis on an open Reader falls back to Source and resumes after diffoff", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local left_win = vim.api.nvim_get_current_win()
  local long_lines = vim.deepcopy(left_lines)
  for i = 1, 80 do
    long_lines[#long_lines + 1] = "| Row " .. i .. " | " .. string.rep("long cell 内容 ", 8) .. " |"
  end
  local left = make_buffer(long_lines)
  vim.api.nvim_win_set_buf(left_win, left)
  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  local right = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(right_win, right)
  vim.api.nvim_set_current_win(left_win)
  local opened = plugin.reader_preview({ auto = true })
  h.assert_true("Reader opened before diffing", reader.is_reader(opened))
  vim.fn.winrestview({ lnum = 45, col = 4, topline = 40 })
  local expected = vim.fn.winsaveview()
  h.assert_true("fixture is scrolled", expected.topline > 1)
  vim.api.nvim_set_current_win(right_win)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)
  wait_for(function()
    return not reader.is_reader(vim.api.nvim_win_get_buf(left_win)) and vim.wo[left_win].diff
  end)

  h.assert_false("left window shows Source, not Reader", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
  h.assert_eq("left window shows its Source buffer", vim.api.nvim_win_get_buf(left_win), left)
  h.assert_true("left window keeps diff", vim.wo[left_win].diff)
  h.assert_true("right window keeps diff", vim.wo[right_win].diff)
  h.assert_eq("diff leave does not pause Source", plugin.state.paused_buffers[left], nil)

  vim.cmd("diffoff!")
  wait_for(function()
    return reader.is_reader(vim.api.nvim_win_get_buf(left_win))
  end)
  h.assert_true("Reader resumes on the left window after diffoff", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
  local restored = vim.api.nvim_win_call(left_win, vim.fn.winsaveview)
  h.assert_eq("Reader cursor survives diff suspend", restored.lnum, expected.lnum)
  h.assert_eq("Reader topline survives diff suspend", restored.topline, expected.topline)
  h.assert_eq("Reader column survives diff suspend", restored.col, expected.col)

  vim.api.nvim_set_current_win(left_win)
  plugin.close_reader()
  vim.api.nvim_win_close(right_win, true)
  delete_buffer(left)
  delete_buffer(right)
  plugin.state.paused_buffers = {}
end)

h.test("manually opened Reader returns after diffoff when auto_preview is off", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  local winid = vim.api.nvim_get_current_win()
  local source = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(winid, source)
  local opened = plugin.reader_preview()
  h.assert_true("manual Reader opened", reader.is_reader(opened))

  vim.cmd("vsplit")
  local other_win = vim.api.nvim_get_current_win()
  local other = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(other_win, other)

  vim.api.nvim_win_call(winid, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(other_win, function()
    vim.cmd("diffthis")
  end)
  wait_for(function()
    return not reader.is_reader(vim.api.nvim_win_get_buf(winid)) and vim.wo[winid].diff
  end)
  h.assert_false("manual Reader yields Source for diff", reader.is_reader(vim.api.nvim_win_get_buf(winid)))

  vim.cmd("diffoff!")
  wait_for(function()
    return reader.is_reader(vim.api.nvim_win_get_buf(winid))
  end)
  h.assert_true("manual Reader returns after diffoff", reader.is_reader(vim.api.nvim_win_get_buf(winid)))

  vim.api.nvim_set_current_win(winid)
  plugin.close_reader()
  vim.api.nvim_win_close(other_win, true)
  delete_buffer(source)
  delete_buffer(other)
  plugin.state.paused_buffers = {}
end)

h.test("paused Source is not resurrected when a suspended diff turns off", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local winid = vim.api.nvim_get_current_win()
  local source = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(winid, source)
  h.assert_true("auto Reader opened", reader.is_reader(plugin.reader_preview({ auto = true })))

  vim.cmd("vsplit")
  local other_win = vim.api.nvim_get_current_win()
  local other = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(other_win, other)

  vim.api.nvim_win_call(winid, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(other_win, function()
    vim.cmd("diffthis")
  end)
  wait_for(function()
    return vim.api.nvim_win_get_buf(winid) == source and vim.wo[winid].diff
  end)
  vim.api.nvim_win_call(winid, plugin.disable_auto_preview)

  vim.cmd("diffoff!")
  wait_for(function()
    return false
  end, 80)
  h.assert_false("paused Source stays in Source after diffoff", reader.is_reader(vim.api.nvim_win_get_buf(winid)))
  h.assert_eq("paused Source buffer remains", vim.api.nvim_win_get_buf(winid), source)

  vim.api.nvim_win_close(other_win, true)
  delete_buffer(source)
  delete_buffer(other)
  plugin.state.paused_buffers = {}
end)

h.test("diffupdate does not refresh a neighbor Markdown window", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  local neighbor_win = vim.api.nvim_get_current_win()
  local neighbor = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(neighbor_win, neighbor)

  vim.cmd("vsplit")
  local diff_win = vim.api.nvim_get_current_win()
  local diff_left = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(diff_win, diff_left)
  vim.cmd("vsplit")
  local diff_right_win = vim.api.nvim_get_current_win()
  local diff_right = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(diff_right_win, diff_right)

  vim.api.nvim_win_call(diff_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(diff_right_win, function()
    vim.cmd("diffthis")
  end)
  wait_for(function()
    return vim.wo[diff_win].diff and vim.wo[diff_right_win].diff
  end)

  wait_for(function()
    return false
  end, 50)
  local scheduled = 0
  local original_schedule = plugin.schedule_refresh
  plugin.schedule_refresh = function(opts)
    scheduled = scheduled + 1
    return original_schedule(opts)
  end
  vim.cmd("diffupdate")
  wait_for(function()
    return false
  end, 80)
  plugin.schedule_refresh = original_schedule
  h.assert_eq("hunk update schedules no refresh", scheduled, 0)
  h.assert_false(
    "neighbor is not opened as Reader on diffupdate",
    reader.is_reader(vim.api.nvim_win_get_buf(neighbor_win))
  )
  h.assert_eq("neighbor still shows Source", vim.api.nvim_win_get_buf(neighbor_win), neighbor)

  vim.cmd("diffoff!")
  vim.api.nvim_win_close(diff_right_win, true)
  vim.api.nvim_win_close(diff_win, true)
  delete_buffer(neighbor)
  delete_buffer(diff_left)
  delete_buffer(diff_right)
  plugin.state.paused_buffers = {}
end)

for _, auto_preview in ipairs({ false, true }) do
  h.test("only the diffed window of a shared Source suspends (auto=" .. tostring(auto_preview) .. ")", function()
    local plugin = require("markdown-table-wrap")
    local reader = require("markdown-table-wrap.reader")
    plugin.setup({ auto_preview = auto_preview, preview_mode = "reader", debounce_ms = 0 })

    local source = make_buffer(left_lines)
    local first_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(first_win, source)
    vim.cmd("vsplit")
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second_win, source)

    vim.api.nvim_set_current_win(first_win)
    local first_reader = plugin.reader_preview()
    vim.api.nvim_set_current_win(second_win)
    local second_reader = plugin.reader_preview()
    h.assert_true("first Reader opened", reader.is_reader(first_reader))
    h.assert_true("second Reader opened", reader.is_reader(second_reader))
    h.assert_true("Readers are distinct", first_reader ~= second_reader)

    vim.cmd("vsplit")
    local other_win = vim.api.nvim_get_current_win()
    local other = make_buffer(right_lines)
    vim.api.nvim_win_set_buf(other_win, other)

    vim.api.nvim_win_call(first_win, function()
      vim.cmd("diffthis")
    end)
    vim.api.nvim_win_call(other_win, function()
      vim.cmd("diffthis")
    end)
    wait_for(function()
      return not reader.is_reader(vim.api.nvim_win_get_buf(first_win)) and vim.wo[first_win].diff
    end)

    h.assert_eq("diffed window shows Source", vim.api.nvim_win_get_buf(first_win), source)
    h.assert_true("undiffed window keeps its Reader", reader.is_reader(vim.api.nvim_win_get_buf(second_win)))

    vim.cmd("diffoff!")
    wait_for(function()
      return reader.is_reader(vim.api.nvim_win_get_buf(first_win))
    end)
    h.assert_true("diffed window Reader returns", reader.is_reader(vim.api.nvim_win_get_buf(first_win)))
    h.assert_true("undiffed Reader remains", reader.is_reader(vim.api.nvim_win_get_buf(second_win)))

    vim.api.nvim_set_current_win(first_win)
    plugin.close_reader()
    vim.api.nvim_set_current_win(second_win)
    plugin.close_reader()
    vim.api.nvim_win_close(other_win, true)
    vim.api.nvim_win_close(second_win, true)
    delete_buffer(source)
    delete_buffer(other)
    plugin.state.paused_buffers = {}
  end)
end

for _, shared_source in ipairs({ false, true }) do
  h.test("two Readers resume after diffoff (shared Source=" .. tostring(shared_source) .. ")", function()
    local plugin = require("markdown-table-wrap")
    local reader = require("markdown-table-wrap.reader")
    plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

    local left_win = vim.api.nvim_get_current_win()
    local left = make_buffer(left_lines)
    vim.api.nvim_win_set_buf(left_win, left)
    h.assert_true("left Reader opened", reader.is_reader(plugin.reader_preview({ auto = true })))

    vim.cmd("vsplit")
    local right_win = vim.api.nvim_get_current_win()
    local right = shared_source and left or make_buffer(right_lines)
    vim.api.nvim_win_set_buf(right_win, right)
    h.assert_true("right Reader opened", reader.is_reader(plugin.reader_preview({ auto = true })))

    vim.api.nvim_win_call(left_win, function()
      vim.cmd("diffthis")
    end)
    vim.api.nvim_win_call(right_win, function()
      vim.cmd("diffthis")
    end)
    -- This headless Lua chunk does not yield to Neovim's input loop.
    vim.api.nvim_exec_autocmds("SafeState", {})
    wait_for(function()
      return not reader.is_reader(vim.api.nvim_win_get_buf(left_win))
        and not reader.is_reader(vim.api.nvim_win_get_buf(right_win))
        and vim.wo[left_win].diff
        and vim.wo[right_win].diff
    end)

    h.assert_eq("left window shows Source", vim.api.nvim_win_get_buf(left_win), left)
    h.assert_eq("right window shows Source", vim.api.nvim_win_get_buf(right_win), right)
    h.assert_true("left window is in diff", vim.wo[left_win].diff)
    h.assert_true("right window is in diff", vim.wo[right_win].diff)
    h.assert_eq("left Source is not paused", plugin.state.paused_buffers[left], nil)
    h.assert_eq("right Source is not paused", plugin.state.paused_buffers[right], nil)

    vim.cmd("diffoff!")
    -- This headless Lua chunk does not yield to Neovim's input loop.
    vim.api.nvim_exec_autocmds("SafeState", {})
    wait_for(function()
      return reader.is_reader(vim.api.nvim_win_get_buf(left_win))
        and reader.is_reader(vim.api.nvim_win_get_buf(right_win))
    end)
    h.assert_true("left Reader returns", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
    h.assert_true("right Reader returns", reader.is_reader(vim.api.nvim_win_get_buf(right_win)))

    vim.api.nvim_set_current_win(left_win)
    plugin.close_reader()
    vim.api.nvim_set_current_win(right_win)
    plugin.close_reader()
    vim.api.nvim_win_close(right_win, true)
    delete_buffer(left)
    delete_buffer(right)
    plugin.state.paused_buffers = {}
  end)
end

h.test("manual Reader commands preserve an active diff and Source policy", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "inline", debounce_ms = 0 })
  local source = make_buffer(left_lines)
  vim.api.nvim_set_current_buf(source)
  plugin.pause_buffer(source)
  vim.cmd("diffthis")
  wait_for(function()
    return false
  end, 50)

  local opened = plugin.reader_preview({ silent = true })
  h.assert_eq("API refuses Reader in diff", opened, nil)
  h.assert_true("API preserves diff immediately", vim.wo.diff)
  h.assert_eq("API preserves Source immediately", vim.api.nvim_get_current_buf(), source)
  vim.cmd("MarkdownTableToggleReader")
  vim.cmd("diffupdate")
  wait_for(function()
    return false
  end, 50)
  h.assert_true("manual commands preserve diff", vim.wo.diff)
  h.assert_eq("manual commands preserve Source", vim.api.nvim_get_current_buf(), source)
  h.assert_false("no Reader is created", reader.has_source_readers(source))
  h.assert_true("pause survives refusal", plugin.state.paused_buffers[source])
  h.assert_eq("mode survives refusal", plugin.get_preview_mode(source), "inline")
  h.assert_deep_eq("Source remains unchanged", vim.api.nvim_buf_get_lines(source, 0, -1, false), left_lines)

  vim.cmd("diffoff!")
  delete_buffer(source)
end)

for _, cleanup in ipairs({ "window", "source" }) do
  h.test("diff suspension is released on " .. cleanup .. " cleanup", function()
    local plugin = require("markdown-table-wrap")
    local reader = require("markdown-table-wrap.reader")
    plugin.setup({ auto_preview = false, debounce_ms = 0 })
    local source = make_buffer(left_lines)
    vim.cmd("vsplit")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, source)
    plugin.reader_preview()
    vim.cmd("diffthis")
    vim.api.nvim_exec_autocmds("SafeState", {})
    wait_for(function()
      return plugin.state.window_suspend[winid] ~= nil
    end)
    h.assert_true("suspension recorded", plugin.state.window_suspend[winid])
    if cleanup == "window" then
      vim.api.nvim_win_close(winid, true)
      h.assert_eq("diff edge state released", plugin.state.diff_seen[winid], nil)
    else
      delete_buffer(source)
    end
    h.assert_eq("suspension released", plugin.state.window_suspend[winid], nil)
    vim.cmd("diffoff!")
    wait_for(function()
      return false
    end, 50)
    h.assert_false("cleanup never resurrects Reader", reader.has_source_readers(source))
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    delete_buffer(source)
  end)
end
