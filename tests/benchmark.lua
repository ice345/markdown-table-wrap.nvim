local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
package.path = table.concat({ root .. "/?.lua", root .. "/?/init.lua", package.path }, ";")

local parser = require("markdown-table-wrap.parser")

local function elapsed_ms(callback)
  collectgarbage("collect")
  local started = (vim.uv or vim.loop).hrtime()
  local result = callback()
  return ((vim.uv or vim.loop).hrtime() - started) / 1e6, result
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

  local cold_ms, reader_bufnr = elapsed_ms(function()
    return require("markdown-table-wrap.reader").open(source_bufnr, plugin.get_buffer_config(source_bufnr))
  end)
  assert(reader_bufnr, "Reader did not open")

  local rendered_lines = vim.api.nvim_buf_line_count(reader_bufnr)
  local extmarks =
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, require("markdown-table-wrap.reader").namespace(), 0, -1, {})
  local movement_ms = elapsed_ms(function()
    for _ = 1, 500 do
      vim.cmd("normal! gg")
      vim.cmd("normal! G")
    end
  end)
  local refresh_ms = elapsed_ms(function()
    require("markdown-table-wrap.reader").refresh(reader_bufnr)
  end)

  print(string.format("large Reader source   %8d lines", #lines))
  print(string.format("large Reader output   %8d lines  %d extmark(s)", rendered_lines, extmarks))
  print(string.format("large Reader open     %8.2f ms", cold_ms))
  print(string.format("large Reader refresh  %8.2f ms", refresh_ms))
  print(string.format("500 gg/G pairs        %8.2f ms", movement_ms))
end
