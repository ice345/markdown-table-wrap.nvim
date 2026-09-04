local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
package.path = table.concat({ root .. "/?.lua", root .. "/?/init.lua", package.path }, ";")

local parser = require("markdown-table-wrap.parser")
local uv = vim.uv or vim.loop

local function elapsed_ms(callback)
  collectgarbage("collect")
  local started = uv.hrtime()
  local result = callback()
  return (uv.hrtime() - started) / 1e6, result
end

local function profile_lua_heap(callback)
  collectgarbage("collect")
  local before_kb = collectgarbage("count")
  collectgarbage("stop")
  local started = uv.hrtime()
  local ok, result = pcall(callback)
  local duration_ms = (uv.hrtime() - started) / 1e6
  local peak_delta_kb = math.max(0, collectgarbage("count") - before_kb)
  collectgarbage("restart")
  collectgarbage("collect")
  local retained_delta_kb = math.max(0, collectgarbage("count") - before_kb)
  if not ok then
    error(result)
  end
  return duration_ms, result, peak_delta_kb, retained_delta_kb
end

local scenarios = {}

local prose = {}
for index = 1, 10000 do
  prose[index] = "ordinary Markdown prose without a table " .. index
end
scenarios["10k prose"] = prose

local invalid = {}
for index = 1, 10000 do
  invalid[index] = "candidate | without | delimiter " .. index
end
scenarios["10k invalid pipes"] = invalid

local many = {}
for index = 1, 500 do
  vim.list_extend(many, {
    "| Name | Value |",
    "| --- | --- |",
    "| item " .. index .. " | `code_" .. index .. "` |",
    "",
  })
end
scenarios["500 small tables"] = many

local semantic = { "| Name | Detail |", "| --- | --- |" }
for index = 1, 1000 do
  table.insert(
    semantic,
    "| [item](docs/path_("
      .. index
      .. ").md) | **bold** `code_token_"
      .. index
      .. "` <https://example.com/"
      .. index
      .. "> |"
  )
end
scenarios["1k semantic rows"] = semantic

for name, lines in pairs(scenarios) do
  local duration, tables = elapsed_ms(function()
    return parser.parse_lines(lines)
  end)
  print(string.format("%-20s %8.2f ms  %d table(s)  %d line(s)", name, duration, #tables, #lines))
end

if vim.env.MARKDOWN_TABLE_WRAP_BENCH_HOT == "1" then
  vim.o.columns = 110
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    debounce_ms = 80,
  })

  local lines = { "| Name | Link | Detail |", "| --- | --- | --- |" }
  for index = 1, 200 do
    lines[#lines + 1] = string.format(
      "| item %d | [docs](docs/item-%d.md) | **bold** `code_%d` and ordinary prose |",
      index,
      index,
      index
    )
  end

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)

  local config_ms = elapsed_ms(function()
    for _ = 1, 5000 do
      assert(plugin.get_buffer_config(bufnr).preview_mode == "inline")
    end
  end)

  local theme = require("markdown-table-wrap.theme")
  local ensure_theme = theme.ensure or theme.apply
  local theme_ms = elapsed_ms(function()
    for _ = 1, 1000 do
      ensure_theme(plugin.config)
    end
  end)

  local table_info = assert(parser.parse_all(bufnr)[1])
  local render = require("markdown-table-wrap.render")
  local rendered = render.render_table(table_info, plugin.get_buffer_config(bufnr))
  local cache = require("markdown-table-wrap.cache")
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  cache.set(bufnr, "benchmark-copy", "stable", changedtick, rendered)
  local cache_copy_ms = elapsed_ms(function()
    for _ = 1, 500 do
      assert(cache.get(bufnr, "benchmark-copy", "stable", changedtick))
    end
  end)
  local cache_ref_ms = elapsed_ms(function()
    for _ = 1, 500 do
      assert(cache.get_ref(bufnr, "benchmark-copy", "stable", changedtick))
    end
  end)
  local render_config = plugin.get_buffer_config(bufnr)
  local render_hit_ms = elapsed_ms(function()
    for _ = 1, 500 do
      assert(render.render_table(table_info, render_config))
    end
  end)
  local render_ref_ms = elapsed_ms(function()
    for _ = 1, 500 do
      assert(render.render_table_ref(table_info, render_config))
    end
  end)

  local scheduled = 0
  local schedule_refresh = plugin.schedule_refresh
  plugin.schedule_refresh = function()
    scheduled = scheduled + 1
  end
  local scroll_ms = elapsed_ms(function()
    for _ = 1, 1000 do
      vim.api.nvim_exec_autocmds("WinScrolled", { modeline = false })
    end
  end)
  local scroll_schedules = scheduled
  scheduled = 0
  local mode_ms = elapsed_ms(function()
    for _ = 1, 1000 do
      vim.api.nvim_exec_autocmds("ModeChanged", { modeline = false })
    end
  end)
  plugin.schedule_refresh = schedule_refresh

  print(string.format("5000 config copies    %8.2f ms", config_ms))
  print(string.format("1000 theme ensures    %8.2f ms", theme_ms))
  print(string.format("500 cache-hit copies  %8.2f ms", cache_copy_ms))
  print(string.format("500 cache-hit refs    %8.2f ms", cache_ref_ms))
  print(string.format("500 render cache hits %8.2f ms", render_hit_ms))
  print(string.format("500 render ref hits   %8.2f ms", render_ref_ms))
  print(string.format("1000 WinScrolled      %8.2f ms  %d refresh schedule(s)", scroll_ms, scroll_schedules))
  print(string.format("1000 ModeChanged      %8.2f ms  %d refresh schedule(s)", mode_ms, scheduled))
end

if vim.env.MARKDOWN_TABLE_WRAP_BENCH_READER == "1" then
  vim.o.columns = 110
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 0.9,
    min_col_width = 8,
    max_col_width = 50,
    row_separator = true,
  })

  local lines = {
    "| mechanism | current experiment candidate | program/API form | stability and version constraint | smallest defensible conclusion |",
    "| --- | --- | --- | --- | --- |",
  }
  for _ = 1, 4000 do
    lines[#lines + 1] =
      '| kprobe/kretprobe | `kprobe:<discovered_function>` | `SEC("kprobe/<function>")` / `SEC("kretprobe/<function>")` | kernel function ABI、符号和版本 | 观察实现函数 entry/return；函数可能服务多个调用路径 |'
  end

  local source_bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[source_bufnr].swapfile = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(source_bufnr)

  local theme = require("markdown-table-wrap.theme")
  local theme_method = theme.ensure and "ensure" or "apply"
  local original_theme_apply = theme[theme_method]
  local original_set_extmark = vim.api.nvim_buf_set_extmark
  local function measure_reader_api(callback)
    local theme_calls = 0
    local theme_ns = 0
    local extmark_calls = 0
    local extmark_ns = 0
    theme[theme_method] = function(...)
      local started = uv.hrtime()
      local result = original_theme_apply(...)
      theme_ns = theme_ns + uv.hrtime() - started
      theme_calls = theme_calls + 1
      return result
    end
    vim.api.nvim_buf_set_extmark = function(...)
      local started = uv.hrtime()
      local result = original_set_extmark(...)
      extmark_ns = extmark_ns + uv.hrtime() - started
      extmark_calls = extmark_calls + 1
      return result
    end
    local ok, duration_ms, result = pcall(elapsed_ms, callback)
    theme[theme_method] = original_theme_apply
    vim.api.nvim_buf_set_extmark = original_set_extmark
    if not ok then
      error(duration_ms)
    end
    return duration_ms, result, theme_ns / 1e6, theme_calls, extmark_ns / 1e6, extmark_calls
  end

  local reader = require("markdown-table-wrap.reader")
  local cold_ms, reader_bufnr, cold_theme_ms, cold_theme_calls, cold_extmark_ms, cold_extmark_calls = measure_reader_api(
    function()
      return reader.open(source_bufnr, plugin.get_buffer_config(source_bufnr))
    end
  )
  assert(reader_bufnr, "Reader did not open")

  assert(reader.close(reader_bufnr) == source_bufnr, "Reader did not close for the heap pass")
  plugin.state.refresh_epoch = plugin.state.refresh_epoch + 1
  plugin.state.refresh_tokens = {}
  require("markdown-table-wrap.cache").clear()
  local cold_heap_ms, heap_reader_bufnr, cold_peak_kb, cold_retained_kb = profile_lua_heap(function()
    return require("markdown-table-wrap.reader").open(source_bufnr, plugin.get_buffer_config(source_bufnr))
  end)
  reader_bufnr = heap_reader_bufnr
  assert(reader_bufnr, "Reader did not open for the heap pass")

  local rendered_lines = vim.api.nvim_buf_line_count(reader_bufnr)
  local extmarks =
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, require("markdown-table-wrap.reader").namespace(), 0, -1, {})
  local movement_ms = elapsed_ms(function()
    for _ = 1, 500 do
      vim.cmd("normal! gg")
      vim.cmd("normal! G")
    end
  end)
  local refresh_ms, _, refresh_theme_ms, refresh_theme_calls, refresh_extmark_ms, refresh_extmark_calls = measure_reader_api(
    function()
      return reader.refresh(reader_bufnr)
    end
  )
  local refresh_heap_ms, _, refresh_peak_kb, refresh_retained_kb = profile_lua_heap(function()
    return reader.refresh(reader_bufnr)
  end)
  local snapshot_ms, snapshot = elapsed_ms(function()
    return reader.get_state(reader_bufnr)
  end)
  local target
  for row, line_object in ipairs(snapshot.line_objects or {}) do
    local cell = type(line_object) == "table" and (line_object.cells or {})[1] or nil
    if cell and cell.row_index == 1 then
      target = { row, cell.start_col }
      break
    end
  end
  assert(target, "Reader benchmark could not resolve a cell")
  vim.api.nvim_win_set_cursor(0, target)
  local local_cell_ms = elapsed_ms(function()
    for _ = 1, 500 do
      local cell = assert(reader.cell_at_cursor(reader_bufnr))
      assert(reader.cell_segments(reader_bufnr, cell))
      assert(reader.line_object(reader_bufnr, target[1]))
    end
  end)

  print(string.format("large Reader source   %8d lines", #lines))
  print(string.format("large Reader output   %8d lines  %d extmark(s)", rendered_lines, extmarks))
  print(string.format("large Reader open     %8.2f ms", cold_ms))
  print(
    string.format(
      "  GC-paused heap pass %8.2f ms  peak %.2f MiB  retained %.2f MiB",
      cold_heap_ms,
      cold_peak_kb / 1024,
      cold_retained_kb / 1024
    )
  )
  print(string.format("  theme API           %8.2f ms  %d call(s)", cold_theme_ms, cold_theme_calls))
  print(string.format("  extmark API         %8.2f ms  %d call(s)", cold_extmark_ms, cold_extmark_calls))
  print(string.format("large Reader refresh  %8.2f ms", refresh_ms))
  print(
    string.format(
      "  GC-paused heap pass %8.2f ms  peak %.2f MiB  retained %.2f MiB",
      refresh_heap_ms,
      refresh_peak_kb / 1024,
      refresh_retained_kb / 1024
    )
  )
  print(string.format("  theme API           %8.2f ms  %d call(s)", refresh_theme_ms, refresh_theme_calls))
  print(string.format("  extmark API         %8.2f ms  %d call(s)", refresh_extmark_ms, refresh_extmark_calls))
  print(string.format("500 gg/G pairs        %8.2f ms", movement_ms))
  print(string.format("full state snapshot   %8.2f ms", snapshot_ms))
  print(string.format("500 local cell reads  %8.2f ms", local_cell_ms))
end
