local h = require("tests.helpers")

local table_lines = {
  "| A | B |",
  "| --- | --- |",
  "| one | two |",
}

local function delete_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

h.test("Reader mappings can be disabled without removing Plug actions", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    mappings = { reader = false, float = false },
  })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local reader_bufnr = plugin.reader_preview()
    h.assert_eq("disabled Reader has no local normal mappings", #vim.api.nvim_buf_get_keymap(reader_bufnr, "n"), 0)
    h.assert_true("Plug action remains available", vim.fn.maparg("<Plug>(MarkdownTableWrapEditSource)", "n") ~= "")
    require("markdown-table-wrap.reader").close(reader_bufnr)
  end)
end)

h.test("Reader passthrough can route custom H and L workflows", function()
  local plugin = require("markdown-table-wrap")
  local callback_calls = 0
  plugin.setup({
    auto_preview = false,
    mappings = {
      reader = {
        passthrough = {
          H = "next_buffer",
          L = { policy = "leave" },
        },
      },
    },
  })

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  local target_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.bo[target_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.api.nvim_buf_set_lines(target_bufnr, 0, -1, false, { "target" })
  vim.bo[source_bufnr].modified = false
  vim.bo[target_bufnr].modified = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.keymap.set("n", "L", function()
    callback_calls = callback_calls + 1
  end, { buffer = source_bufnr })

  vim.api.nvim_set_current_buf(source_bufnr)
  local first_reader = plugin.reader_preview()
  vim.cmd("normal H")
  h.assert_false("H leaves Reader", require("markdown-table-wrap.reader").is_reader(first_reader))
  h.assert_eq("H action advances from Source to the next buffer", vim.api.nvim_get_current_buf(), target_bufnr)

  vim.api.nvim_set_current_buf(source_bufnr)
  local second_reader = plugin.reader_preview()
  vim.cmd("normal L")
  h.assert_false("L leave policy closes Reader", require("markdown-table-wrap.reader").is_reader(second_reader))
  h.assert_eq("L invokes captured Source mapping exactly once", callback_calls, 1)
  h.assert_eq("L leaves Source visible", vim.api.nvim_get_current_buf(), source_bufnr)

  delete_buffer(source_bufnr)
  delete_buffer(target_bufnr)
end)

h.test("Float refresh preserves Source auto-preview state", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = true, preview_mode = "float" })
  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    plugin.float_preview()
    local first_float = plugin.state.buf
    h.assert_true("Float refresh action succeeds", plugin.action("refresh"))
    h.assert_true("Float is recreated", plugin.state.buf ~= nil and plugin.state.buf ~= first_float)
    h.assert_eq("Float refresh does not pause Source", plugin.state.paused_buffers[source_bufnr], nil)
    plugin.close_preview()
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)

h.test("Reader split tab and explicit buffer actions keep Source ownership", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false })

  local target_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[target_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(target_bufnr, 0, -1, false, { "target" })
  vim.bo[target_bufnr].modified = false

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local first_reader = plugin.reader_preview()
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)
    h.assert_true("split Source action succeeds", plugin.action("split_source"))
    h.assert_false("split action disposes Reader", reader.is_reader(first_reader))
    h.assert_eq("split action keeps Source current", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_eq("split action creates one window", #vim.api.nvim_tabpage_list_wins(0), windows_before + 1)
    vim.api.nvim_win_close(0, true)

    local second_reader = plugin.reader_preview()
    local tabs_before = vim.fn.tabpagenr("$")
    h.assert_true("tab Source action succeeds", plugin.action("tab_source"))
    h.assert_false("tab action disposes Reader", reader.is_reader(second_reader))
    h.assert_eq("tab action keeps Source current", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_eq("tab action creates one tab", vim.fn.tabpagenr("$"), tabs_before + 1)
    vim.cmd("tabclose")

    local third_reader = plugin.reader_preview()
    h.assert_true("explicit buffer action succeeds", plugin.action("select_buffer", { target_bufnr = target_bufnr }))
    h.assert_false("buffer selection disposes Reader", reader.is_reader(third_reader))
    h.assert_eq("explicit target becomes current", vim.api.nvim_get_current_buf(), target_bufnr)
    vim.api.nvim_set_current_buf(source_bufnr)
    plugin.state.paused_buffers[source_bufnr] = nil
  end)

  delete_buffer(target_bufnr)
end)

local function listed_except_current()
  local current = vim.api.nvim_get_current_buf()
  local listed = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= current then
      listed[info.bufnr] = true
    end
  end
  return listed
end

h.test("with_source reveals Source so buffer pickers select the last listed file", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, preview_mode = "reader" })

  local previous = vim.api.nvim_create_buf(true, false)
  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[previous].swapfile = false
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(previous, 0, -1, false, { "previous" })
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.bo[previous].modified = false
  vim.bo[source_bufnr].modified = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_set_current_buf(source_bufnr)

  local reader_bufnr = plugin.reader_preview()
  h.assert_eq("Reader stays unlisted", vim.fn.buflisted(reader_bufnr), 0)
  h.assert_true("Reader current includes Source in the picker list", listed_except_current()[source_bufnr] == true)

  local seen
  local callback_paused
  local during
  plugin.with_source(function()
    seen = vim.api.nvim_get_current_buf()
    callback_paused = plugin.state.paused_buffers[source_bufnr] == true
    during = listed_except_current()
  end)

  h.assert_eq("with_source callback runs on Source", seen, source_bufnr)
  h.assert_true("with_source suppresses auto-preview while the picker snapshots", callback_paused)
  h.assert_false("with_source disposes Reader", reader.is_reader(reader_bufnr))
  h.assert_eq("Source is excluded from the picker list while current", during[source_bufnr], nil)
  h.assert_true("previous listed file remains the Enter target", during[previous] == true)
  h.assert_eq("with_source does not set persistent pause", plugin.state.paused_buffers[source_bufnr], nil)
  h.assert_eq("with_source leaves Source current when the picker cancels", vim.api.nvim_get_current_buf(), source_bufnr)

  delete_buffer(source_bufnr)
  delete_buffer(previous)
end)

h.test("with_source keeps Source unpaused after switching to another buffer", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, preview_mode = "reader" })

  local previous = vim.api.nvim_create_buf(true, false)
  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[previous].swapfile = false
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(previous, 0, -1, false, { "previous" })
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.bo[previous].modified = false
  vim.bo[source_bufnr].modified = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_set_current_buf(source_bufnr)

  plugin.reader_preview()
  plugin.with_source(function()
    vim.api.nvim_set_current_buf(previous)
  end)

  h.assert_eq("picker selection becomes current", vim.api.nvim_get_current_buf(), previous)
  h.assert_eq("selected leave does not pause Source", plugin.state.paused_buffers[source_bufnr], nil)

  delete_buffer(source_bufnr)
  delete_buffer(previous)
end)

h.test("with_source restores persistent pause and can reopen Reader after cancel", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.bo[source_bufnr].modified = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_set_current_buf(source_bufnr)

  local reader_bufnr = plugin.reader_preview()
  plugin.state.paused_buffers[source_bufnr] = true
  plugin.with_source(function() end)
  h.assert_eq("existing pause survives with_source", plugin.state.paused_buffers[source_bufnr], true)
  h.assert_false("paused cancel does not reopen Reader", reader.is_reader(vim.api.nvim_get_current_buf()))
  h.assert_false("paused cancel keeps Reader disposed", reader.is_reader(reader_bufnr))

  plugin.state.paused_buffers[source_bufnr] = nil
  reader_bufnr = plugin.reader_preview()
  plugin.with_source(function() end)
  local reopened = vim.wait(200, function()
    return reader.is_reader(vim.api.nvim_get_current_buf())
  end, 10)
  h.assert_true("unpaused cancel reopens Reader", reopened)
  h.assert_false("reopen replaces the previous Reader", reader.is_reader(reader_bufnr))

  local current = vim.api.nvim_get_current_buf()
  if reader.is_reader(current) then
    reader.close(current)
  end
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end)

h.test("with_source closes Float and is a no-op in Inline and ordinary buffers", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  plugin.setup({ auto_preview = false, preview_mode = "float" })

  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    plugin.float_preview()
    h.assert_true("Float opens", plugin.state.buf ~= nil)
    local seen
    plugin.with_source(function()
      seen = vim.api.nvim_get_current_buf()
    end)
    h.assert_eq("Float with_source runs on Source", seen, source_bufnr)
    h.assert_eq("Float with_source closes the float", plugin.state.buf, nil)
    h.assert_eq("Float with_source does not pause Source", plugin.state.paused_buffers[source_bufnr], nil)
  end)

  plugin.setup({
    auto_preview = true,
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
  })
  h.with_buffer(table_lines, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    plugin.refresh_auto({ bufnr = source_bufnr, force = true })
    h.assert_true("Inline is active", inline.is_active(source_bufnr))
    local seen
    plugin.with_source(function()
      seen = vim.api.nvim_get_current_buf()
    end)
    h.assert_eq("Inline with_source keeps Source current", seen, source_bufnr)
    h.assert_true("Inline with_source leaves rendering in place", inline.is_active(source_bufnr))
    inline.clear(source_bufnr)
  end)

  h.with_buffer({ "plain" }, function(bufnr)
    vim.bo[bufnr].filetype = "text"
    local seen
    plugin.with_source(function()
      seen = vim.api.nvim_get_current_buf()
    end)
    h.assert_eq("ordinary buffers just run the callback", seen, bufnr)
  end)
end)

h.test("source_command runs an Ex command from Source context", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, preview_mode = "reader" })

  local seen
  vim.api.nvim_create_user_command("MarkdownTableWrapTestCmd", function()
    seen = vim.api.nvim_get_current_buf()
  end, {})

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.bo[source_bufnr].modified = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_set_current_buf(source_bufnr)
  plugin.reader_preview()
  plugin.source_command("MarkdownTableWrapTestCmd")
  h.assert_eq("source_command runs on Source", seen, source_bufnr)
  vim.api.nvim_del_user_command("MarkdownTableWrapTestCmd")
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end)
