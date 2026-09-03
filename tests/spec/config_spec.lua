local h = require("tests.helpers")

h.test("configuration resolution returns isolated normalized copies", function()
  local config = require("markdown-table-wrap.config")
  local first = config.defaults()
  first.reader.wrap = false
  first.mappings.reader.cell.yank = "custom"

  local second = config.defaults()
  h.assert_true("nested Reader defaults are isolated", second.reader.wrap)
  h.assert_eq("nested mapping defaults are isolated", second.mappings.reader.cell.yank, "yic")

  local opts = {
    min_col_width = 0,
    reader = { conceallevel = 9 },
    mappings = { reader = { cell = { put = "gpc" } } },
  }
  local resolved = config.resolve(opts)
  h.assert_eq("resolved widths are normalized", resolved.min_col_width, 1)
  h.assert_eq("resolved Reader options are normalized", resolved.reader.conceallevel, 3)
  h.assert_eq("partial cell mappings retain defaults", resolved.mappings.reader.cell.yank, "yic")
  h.assert_eq("partial cell mappings retain overrides", resolved.mappings.reader.cell.put, "gpc")
  h.assert_eq("resolution does not mutate caller options", opts.reader.conceallevel, 9)
  h.assert_eq("resolution does not add defaults to caller options", opts.mappings.reader.cell.yank, nil)
end)

h.test("setup normalizes invalid configuration without breaking rendering", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    max_width_ratio = 9,
    min_col_width = 0,
    max_col_width = -1,
    debounce_ms = -1,
    overlay_priority = 0,
    preview_mode = "unknown",
    inline_mode = "unknown",
    inline_position = "sideways",
    table_border = "double",
    inline_virtual_text = "invalid",
    inline_wrap_scope = "invalid",
    highlight_preset = "not-a-preset",
    extra_filetypes = { "text", 1 },
    reader = false,
    link = false,
    themes = false,
    highlights = false,
    theme_dir = false,
    discovery = { backend = "invalid" },
    cache = false,
    wide_table = {
      mode = "invalid",
      viewport = { start_column = 0, column_count = 0, marker = "" },
      columns = { bad = "rule", [1] = { min = 9, max = 2, width = 0, weight = -1, priority = -2 } },
    },
  })

  h.assert_eq("ratio is capped to window width", plugin.config.max_width_ratio, 1)
  h.assert_eq("minimum width is positive", plugin.config.min_col_width, 1)
  h.assert_eq("maximum width follows minimum", plugin.config.max_col_width, 1)
  h.assert_eq("negative debounce is clamped", plugin.config.debounce_ms, 0)
  h.assert_eq("overlay priority is positive", plugin.config.overlay_priority, 1)
  h.assert_eq("invalid preview mode falls back", plugin.config.preview_mode, "reader")
  h.assert_eq("invalid inline mode falls back", plugin.config.inline_mode, "replace")
  h.assert_eq("invalid inline position falls back", plugin.config.inline_position, "above")
  h.assert_eq("invalid table border falls back", plugin.config.table_border, "rounded")
  h.assert_eq("invalid virtual text mode falls back", plugin.config.inline_virtual_text, "overlay")
  h.assert_eq("invalid wrap scope falls back", plugin.config.inline_wrap_scope, "cursor")
  h.assert_eq("invalid preset falls back", plugin.config.highlight_preset, "default")
  h.assert_deep_eq("invalid filetypes are ignored", plugin.config.extra_filetypes, {})
  h.assert_true("reader config is restored", type(plugin.config.reader) == "table")
  h.assert_true("link config is restored", type(plugin.config.link) == "table")
  h.assert_deep_eq("invalid themes are ignored", plugin.config.themes, {})
  h.assert_deep_eq("invalid highlights are ignored", plugin.config.highlights, {})
  h.assert_eq("invalid theme directory is ignored", plugin.config.theme_dir, nil)
  h.assert_eq("invalid discovery backend uses auto", plugin.config.discovery.backend, "auto")
  h.assert_true("invalid cache config restores defaults", plugin.config.cache.enabled)
  h.assert_eq("invalid wide-table mode falls back", plugin.config.wide_table.mode, "wrap")
  h.assert_eq("wide-table viewport start is positive", plugin.config.wide_table.viewport.start_column, 1)
  h.assert_eq("wide-table viewport count is positive", plugin.config.wide_table.viewport.column_count, 1)
  h.assert_eq("wide-table marker is restored", plugin.config.wide_table.viewport.marker, "…")
  h.assert_eq("wide-table column minimum is retained", plugin.config.wide_table.columns[1].min, 9)
  h.assert_eq("wide-table maximum follows minimum", plugin.config.wide_table.columns[1].max, 9)
  h.assert_eq("wide-table fixed width is positive", plugin.config.wide_table.columns[1].width, 1)
  h.assert_eq("wide-table weight is non-negative", plugin.config.wide_table.columns[1].weight, 0)
  h.assert_eq("wide-table priority is non-negative", plugin.config.wide_table.columns[1].priority, 0)
end)

h.test("setup installs gx when Markdown filetype predates plugin loading", function()
  local plugin = require("markdown-table-wrap")

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [YouTube](https://youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.setup({ auto_preview = false, map_gx = true })

    local mapping = nil
    for _, item in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if item.lhs == "gx" then
        mapping = item
        break
      end
    end

    h.assert_true("gx mapping is present", mapping ~= nil)
    h.assert_eq("gx mapping belongs to this plugin", mapping.desc, "Open Markdown table link")
  end)
end)

h.test("safe defaults leave gx untouched and normalize Reader options", function()
  local plugin = require("markdown-table-wrap")

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.setup({
      auto_preview = false,
      reader = {
        auto_open = "invalid",
        conceallevel = 2.8,
        concealcursor = "invalid",
      },
    })

    local plugin_mapping = false
    for _, item in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if item.lhs == "gx" and item.desc == "Open Markdown table link" then
        plugin_mapping = true
      end
    end

    h.assert_false("gx override is opt-in", plugin.config.map_gx)
    h.assert_false("default setup does not add a buffer-local gx", plugin_mapping)
    h.assert_eq("invalid Reader auto-open falls back", plugin.config.reader.auto_open, "has_table")
    h.assert_eq("Reader conceallevel is an integer", plugin.config.reader.conceallevel, 2)
    h.assert_eq("invalid concealcursor falls back", plugin.config.reader.concealcursor, "nvc")
  end)
end)

h.test("individual Reader and Float keys can be disabled", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    mappings = {
      reader = { close = false, edit = false, open_link = false, insert = false },
      float = { close = false, open_link = false },
    },
  })
  h.assert_deep_eq("Reader insert keys can be disabled", plugin.config.mappings.reader.insert, {})
  h.assert_false("Float close keys can be disabled", plugin.config.mappings.float.close)
end)

h.test("ColorScheme reapplies configured highlights", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    highlights = { border = { fg = "#123456" } },
  })

  vim.api.nvim_set_hl(0, "MarkdownTableWrapBorder", { fg = "#ffffff" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  local highlight = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder", link = false })
  h.assert_eq("configured border color is restored", highlight.fg, 0x123456)
end)

h.test("all documented commands exist after setup", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  for _, command in ipairs({
    "MarkdownTablePreview",
    "MarkdownTableReader",
    "MarkdownTableEditSource",
    "MarkdownTableFloatPreview",
    "MarkdownTableToggleAutoPreview",
    "MarkdownTableRefresh",
    "MarkdownTableToggleInline",
    "MarkdownTableOpenLink",
    "MarkdownTableOpen",
    "MarkdownTableOpenSplit",
    "MarkdownTableOpenVSplit",
    "MarkdownTableOpenTab",
    "MarkdownTableInspect",
    "MarkdownTableWithSource",
    "MarkdownTableHelp",
    "MarkdownTableScrollDown",
    "MarkdownTableScrollUp",
    "MarkdownTableViewportLeft",
    "MarkdownTableViewportRight",
    "MarkdownTableYankCell",
    "MarkdownTablePutCell",
    "MarkdownTableYankTable",
    "MarkdownTableExport",
  }) do
    h.assert_eq("command exists: " .. command, vim.fn.exists(":" .. command), 2)
  end
end)

h.test("repeated setup replaces plugin autocmds instead of accumulating them", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local first = #vim.api.nvim_get_autocmds({ group = "MarkdownTableWrap" })

  plugin.setup({ auto_preview = false, preview_mode = "inline" })
  local second = #vim.api.nvim_get_autocmds({ group = "MarkdownTableWrap" })

  h.assert_true("plugin registers autocmds", first > 0)
  h.assert_eq("second setup does not duplicate autocmds", second, first)
end)
