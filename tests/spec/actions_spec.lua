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
  h.assert_eq("H navigation does not pause automatic Reader policy", plugin.state.paused_buffers[source_bufnr], nil)

  vim.api.nvim_set_current_buf(source_bufnr)
  local second_reader = plugin.reader_preview()
  vim.cmd("normal L")
  h.assert_false("L leave policy closes Reader", require("markdown-table-wrap.reader").is_reader(second_reader))
  h.assert_eq("L invokes captured Source mapping exactly once", callback_calls, 1)
  h.assert_eq("L leaves Source visible", vim.api.nvim_get_current_buf(), source_bufnr)

  delete_buffer(source_bufnr)
  delete_buffer(target_bufnr)
end)

h.test("Reader buffer navigation returns to Reader while an explicit close returns to Source", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  local target_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.bo[target_bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
  vim.api.nvim_buf_set_lines(target_bufnr, 0, -1, false, { "target" })
  vim.bo[source_bufnr].filetype = "markdown"
  vim.bo[source_bufnr].modified = false
  vim.bo[target_bufnr].modified = false

  vim.api.nvim_set_current_buf(source_bufnr)
  local first_reader = plugin.reader_preview()
  h.assert_true("Reader opens before temporary navigation", reader.is_reader(first_reader))
  h.assert_true("next-buffer action succeeds", plugin.action("next_buffer"))
  h.assert_eq("temporary navigation reaches target", vim.api.nvim_get_current_buf(), target_bufnr)
  h.assert_eq("temporary navigation stays unpaused", plugin.state.paused_buffers[source_bufnr], nil)

  vim.api.nvim_set_current_buf(source_bufnr)
  vim.wait(200, function()
    return reader.is_reader(vim.api.nvim_get_current_buf())
  end, 5)
  h.assert_true("returning after H/L-style navigation restores Reader", reader.is_reader(0))

  h.assert_true("explicit Reader close succeeds", plugin.close_reader())
  h.assert_true("explicit close records Source mode", plugin.state.paused_buffers[source_bufnr])
  vim.api.nvim_set_current_buf(target_bufnr)
  vim.api.nvim_set_current_buf(source_bufnr)
  vim.wait(50)
  h.assert_eq("returning after explicit close stays on Source", vim.api.nvim_get_current_buf(), source_bufnr)
  h.assert_false("returning after explicit close does not reopen Reader", reader.is_reader(0))

  plugin.state.paused_buffers[source_bufnr] = nil
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
