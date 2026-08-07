local h = require("tests.helpers")

local table_lines = {
  "| A | B |",
  "| --- | --- |",
  "| one | two |",
}

local function new_markdown_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  return buf
end

local function delete_buffer(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

h.test("debounced refreshes are isolated by buffer and keep their scheduled target", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 20,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({
    "| C | D |",
    "| --- | --- |",
    "| three | four |",
  })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  inline.clear(buf_a)
  inline.clear(buf_b)
  vim.api.nvim_set_current_win(win_a)
  plugin.schedule_refresh({ bufnr = buf_a, winid = win_a, force = true })
  vim.api.nvim_set_current_win(win_b)
  plugin.schedule_refresh({ bufnr = buf_b, winid = win_b, force = true })

  local refreshed = vim.wait(500, function()
    return inline.is_active(buf_a) and inline.is_active(buf_b)
  end, 10)

  h.assert_true("both buffer refreshes run", refreshed)
  h.assert_true("first buffer receives its own render", inline.is_active(buf_a))
  h.assert_true("second buffer receives its own render", inline.is_active(buf_b))
  h.assert_eq("deferred callbacks preserve the current window", vim.api.nvim_get_current_win(), win_b)
  h.assert_eq("deferred callbacks preserve the current buffer", vim.api.nvim_get_current_buf(), buf_b)

  inline.dispose(buf_a)
  inline.dispose(buf_b)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("repeated setup invalidates refreshes from the previous setup epoch", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, preview_mode = "inline", debounce_ms = 20 })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local original_refresh = plugin.refresh_auto
    local refresh_calls = 0
    plugin.refresh_auto = function()
      refresh_calls = refresh_calls + 1
    end

    plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win() })
    plugin.setup({ auto_preview = false, preview_mode = "inline", debounce_ms = 20 })
    plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win() })
    vim.wait(200, function()
      return refresh_calls >= 1
    end, 10)
    vim.wait(40)

    plugin.refresh_auto = original_refresh
    h.assert_eq("only the current setup epoch refreshes", refresh_calls, 1)
  end)
end)

h.test("interactive mode auto and viewport choices stay buffer local", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    inline_viewport_scrolling = false,
    render_all = true,
    debounce_ms = 0,
  })

  local buf_a = new_markdown_buffer(table_lines)
  local buf_b = new_markdown_buffer(table_lines)
  vim.api.nvim_set_current_buf(buf_a)

  h.assert_true("inline can be enabled in first buffer", plugin.toggle_inline())
  h.assert_eq("first buffer switches to inline", plugin.get_preview_mode(buf_a), "inline")
  h.assert_eq("second buffer keeps reader default", plugin.get_preview_mode(buf_b), "reader")
  h.assert_eq("global preview mode stays immutable", plugin.config.preview_mode, "reader")
  h.assert_false("global auto default stays immutable", plugin.config.auto_preview)

  plugin.toggle_inline_viewport_scrolling()
  h.assert_true("first buffer enables viewport", plugin.get_buffer_config(buf_a).inline_viewport_scrolling)
  h.assert_false("second buffer keeps viewport default", plugin.get_buffer_config(buf_b).inline_viewport_scrolling)
  h.assert_false("global viewport default stays immutable", plugin.config.inline_viewport_scrolling)

  plugin.disable_auto_preview()
  vim.api.nvim_set_current_buf(buf_b)
  h.assert_true("inline can be enabled independently in second buffer", plugin.toggle_inline())
  plugin.disable_auto_preview()
  plugin.enable_auto_preview()

  h.assert_true("second buffer auto preview is enabled", plugin.get_buffer_config(buf_b).auto_preview)
  h.assert_false("first buffer auto preview remains disabled", plugin.get_buffer_config(buf_a).auto_preview)
  h.assert_eq("first buffer keeps its inline mode", plugin.get_preview_mode(buf_a), "inline")
  h.assert_true("first buffer keeps its viewport override", plugin.get_buffer_config(buf_a).inline_viewport_scrolling)
  h.assert_false("global auto default is still immutable", plugin.config.auto_preview)

  inline.dispose(buf_a)
  inline.dispose(buf_b)
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("leaving an inline window or buffer restores its local options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    inline_wrap_scope = "always",
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({ "plain text" })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  vim.wo[win_a].wrap = true
  vim.wo[win_a].conceallevel = 0
  vim.wo[win_a].concealcursor = ""
  vim.api.nvim_set_current_win(win_a)
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })

  h.assert_false("inline disables wrap", vim.wo[win_a].wrap)
  h.assert_eq("inline raises conceallevel", vim.wo[win_a].conceallevel, 2)
  h.assert_eq("inline sets concealcursor", vim.wo[win_a].concealcursor, "nvc")

  vim.api.nvim_set_current_win(win_b)
  h.assert_true("WinLeave restores wrap", vim.wo[win_a].wrap)
  h.assert_eq("WinLeave restores conceallevel", vim.wo[win_a].conceallevel, 0)
  h.assert_eq("WinLeave restores concealcursor", vim.wo[win_a].concealcursor, "")

  vim.api.nvim_set_current_win(win_a)
  h.assert_false("WinEnter reapplies inline wrap", vim.wo[win_a].wrap)
  vim.api.nvim_win_set_buf(win_a, buf_b)
  h.assert_true("BufLeave restores wrap", vim.wo[win_a].wrap)
  h.assert_eq("BufLeave restores conceallevel", vim.wo[win_a].conceallevel, 0)
  h.assert_eq("BufLeave restores concealcursor", vim.wo[win_a].concealcursor, "")

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("BufWipeout disposes all per-buffer runtime state", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    render_all = true,
    debounce_ms = 30,
  })

  local buf = new_markdown_buffer(table_lines)
  vim.api.nvim_set_current_buf(buf)
  plugin.toggle_inline()
  plugin.toggle_inline_viewport_scrolling()
  plugin.pause_buffer(buf)
  plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win(), force = true })
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.wait(80)

  for _, field in ipairs({
    "auto_buffers",
    "buffer_modes",
    "inline_viewports",
    "refresh_tokens",
    "paused_buffers",
    "last_signature",
    "visual_buffers",
    "gx_fallbacks",
    "gx_installed",
    "gx_callbacks",
  }) do
    h.assert_eq(field .. " is cleared for wiped buffer", (plugin.state[field] or {})[buf], nil)
  end
  h.assert_true("wiped buffer is invalid", not vim.api.nvim_buf_is_valid(buf))
  h.assert_true("wiped buffer is no longer the active inline buffer", plugin.state.inline_buf ~= buf)
end)

h.test("repeated setup resets inline viewport offsets", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local opts = {
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    inline_viewport_scrolling = true,
    min_col_width = 4,
    max_col_width = 6,
  }

  local function first_overlay(buf)
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
      local chunks = (mark[4] or {}).virt_text
      if mark[2] == 0 and chunks then
        local text_parts = {}
        for _, chunk in ipairs(chunks) do
          table.insert(text_parts, chunk[1])
        end
        return table.concat(text_parts)
      end
    end
    return nil
  end

  plugin.setup(opts)
  h.with_buffer({
    "| a header that wraps | B |",
    "| --- | --- |",
    "| a body value that wraps | other |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    plugin.refresh_auto({ force = true })
    local initial = first_overlay(buf)

    h.assert_true("long table viewport can scroll", inline.scroll(buf, 1))
    local scrolled = first_overlay(buf)
    h.assert_true("viewport moves away from its initial row", scrolled ~= initial)

    plugin.setup(opts)
    plugin.refresh_auto({ force = true })
    h.assert_eq("setup starts viewport at the top again", first_overlay(buf), initial)
    inline.dispose(buf)
  end)
end)

h.test("reader auto-open requires a table but explicit Reader still opens", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")

  plugin.setup({ debounce_ms = 0 })

  h.with_buffer({ "# Notes", "", "No table in this document." }, function(source_buf)
    vim.bo[source_buf].filetype = "markdown"
    plugin.state.paused_buffers[source_buf] = nil

    h.assert_eq("reader defaults to table-only auto-open", plugin.config.reader.auto_open, "has_table")
    plugin.refresh_auto()
    h.assert_eq("automatic refresh keeps no-table source visible", vim.api.nvim_get_current_buf(), source_buf)
    h.assert_false("automatic refresh does not create Reader", reader.is_reader(0))

    vim.cmd("MarkdownTableReader")
    local reader_buf = vim.api.nvim_get_current_buf()
    h.assert_true("explicit Reader command opens no-table document", reader.is_reader(reader_buf))
    plugin.close_reader()
    plugin.state.paused_buffers[source_buf] = nil

    plugin.setup({ debounce_ms = 0, reader = { auto_open = "always" } })
    plugin.refresh_auto()
    h.assert_true("always policy preserves automatic no-table Reader", reader.is_reader(0))
    plugin.disable_auto_preview()
    h.assert_eq("disabling from Reader returns to source", vim.api.nvim_get_current_buf(), source_buf)
    h.assert_false("disabling from Reader updates source auto state", plugin.get_buffer_config(source_buf).auto_preview)
  end)
end)

h.test("repeated setup reconfigures an open Reader", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false, reader = { wrap = true } })

  h.with_buffer(table_lines, function(source_buf)
    vim.bo[source_buf].filetype = "markdown"
    local reader_buf = plugin.reader_preview()
    h.assert_true("Reader opens before reconfiguration", reader.is_reader(reader_buf))
    h.assert_true("Reader starts with wrap enabled", vim.wo.wrap)

    plugin.setup({ auto_preview = false, reader = { wrap = false } })
    h.assert_true("Reader stays open across setup", reader.is_reader(0))
    h.assert_false("open Reader receives the new window options", vim.wo.wrap)
    plugin.close_reader()
  end)
end)

h.test("repeated setup closes an open floating preview", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, preview_mode = "float" })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    plugin.float_preview()
    local float_win = plugin.state.win
    local float_buf = plugin.state.buf
    h.assert_true("float opens before setup", vim.api.nvim_win_is_valid(float_win))

    plugin.setup({ auto_preview = false, preview_mode = "float" })
    h.assert_true("old float window is closed", not vim.api.nvim_win_is_valid(float_win))
    h.assert_true("old float buffer is deleted", not vim.api.nvim_buf_is_valid(float_buf))
    h.assert_eq("float window state is cleared", plugin.state.win, nil)
    h.assert_eq("float buffer state is cleared", plugin.state.buf, nil)
  end)
end)

h.test("native Reader buffer exits preserve unsaved Source state", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local original_hidden = vim.o.hidden

  plugin.setup({ auto_preview = false, preview_mode = "reader" })
  vim.o.hidden = false

  local function exercise(label, leave)
    local target_bufnr = vim.api.nvim_create_buf(true, false)
    local source_bufnr = vim.api.nvim_create_buf(true, false)
    vim.bo[target_bufnr].swapfile = false
    vim.bo[source_bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(target_bufnr, 0, -1, false, { label .. " target" })
    vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, table_lines)
    vim.bo[target_bufnr].modified = false
    vim.bo[source_bufnr].modified = false
    vim.bo[source_bufnr].filetype = "markdown"
    local source_bufhidden = vim.bo[source_bufnr].bufhidden

    vim.api.nvim_set_current_buf(target_bufnr)
    vim.api.nvim_set_current_buf(source_bufnr)
    vim.bo[source_bufnr].modified = true
    local reader_bufnr = plugin.reader_preview()
    h.assert_eq(label .. " Reader stays unlisted", vim.fn.buflisted(reader_bufnr), 0)

    local ok, err = pcall(leave, reader_bufnr)
    h.assert_true(label .. " command succeeds: " .. tostring(err), ok)
    vim.wait(100, function()
      return not vim.api.nvim_buf_is_valid(reader_bufnr)
    end, 5)

    h.assert_false(label .. " clears Reader state", reader.is_reader(reader_bufnr))
    h.assert_true(label .. " deletes disposable Reader", not vim.api.nvim_buf_is_valid(reader_bufnr))
    h.assert_true(label .. " preserves unsaved Source", vim.bo[source_bufnr].modified)
    h.assert_eq(label .. " restores Source bufhidden", vim.bo[source_bufnr].bufhidden, source_bufhidden)

    delete_buffer(source_bufnr)
    delete_buffer(target_bufnr)
  end

  exercise(":bnext", function()
    vim.cmd("bnext")
  end)
  exercise(":bprevious", function()
    vim.cmd("bprevious")
  end)
  exercise("CTRL-^", function()
    local key = vim.api.nvim_replace_termcodes("<C-^>", true, false, true)
    vim.api.nvim_feedkeys(key, "nx", false)
  end)
  exercise("Reader wipe", function(reader_bufnr)
    vim.api.nvim_buf_delete(reader_bufnr, { force = true })
  end)

  vim.o.hidden = original_hidden
end)

h.test("gx delegates ordinary text to the previous buffer-local mapping", function()
  local plugin = require("markdown-table-wrap")
  local fallback_calls = 0

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "gx", function()
      fallback_calls = fallback_calls + 1
    end, { buffer = buf, silent = true, desc = "Lifecycle test gx fallback" })

    plugin.setup({ auto_preview = false, map_gx = true })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal gx")

    h.assert_eq("previous buffer-local gx mapping is called once", fallback_calls, 1)

    plugin.setup({ auto_preview = false, map_gx = false })
    vim.cmd("normal gx")
    h.assert_eq("disabling the proxy restores the previous mapping", fallback_calls, 2)
  end)
end)

h.test("gx proxy evaluates an existing string expression mapping", function()
  local plugin = require("markdown-table-wrap")
  local expression_calls = 0
  _G.__markdown_table_wrap_test_expr = function()
    expression_calls = expression_calls + 1
    return "<Ignore>"
  end

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "gx", "v:lua.__markdown_table_wrap_test_expr()", {
      buffer = buf,
      expr = true,
      replace_keycodes = false,
      silent = true,
      desc = "Lifecycle string expr gx fallback",
    })

    plugin.setup({ auto_preview = false, map_gx = true })
    vim.cmd("normal gx")
    h.assert_eq("proxy evaluates the previous expression mapping", expression_calls, 1)

    plugin.setup({ auto_preview = false, map_gx = false })
    local restored = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg("gx", "n", false, true)
    end)
    h.assert_true(
      "restored mapping preserves replace_keycodes when reported",
      restored.replace_keycodes == nil or restored.replace_keycodes == 0
    )
    vim.cmd("normal gx")
    h.assert_eq("restored expression mapping still evaluates", expression_calls, 2)
  end)

  _G.__markdown_table_wrap_test_expr = nil
end)

h.test("gx teardown preserves a later user mapping even with the same description", function()
  local plugin = require("markdown-table-wrap")
  local later_calls = 0

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.setup({ auto_preview = false, map_gx = true })

    vim.keymap.set("n", "gx", function()
      later_calls = later_calls + 1
    end, { buffer = buf, desc = "Open Markdown table link" })

    plugin.setup({ auto_preview = false, map_gx = false })
    vim.cmd("normal gx")
    h.assert_eq("later user mapping is not mistaken for the proxy", later_calls, 1)
  end)
end)

h.test("wiping a Source cleans every dependent Reader", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = false })

  local source_bufnr = new_markdown_buffer(table_lines)
  vim.api.nvim_set_current_buf(source_bufnr)
  local reader_bufnr = plugin.reader_preview()
  vim.api.nvim_buf_delete(source_bufnr, { force = true })
  vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(reader_bufnr)
  end, 5)
  h.assert_false("deleted Source removes Reader state", reader.is_reader(reader_bufnr))
  h.assert_false("deleted Source removes Reader buffer", vim.api.nvim_buf_is_valid(reader_bufnr))
end)
