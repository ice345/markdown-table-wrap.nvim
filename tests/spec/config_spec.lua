local h = require("tests.helpers")

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
    "MarkdownTableScrollDown",
    "MarkdownTableScrollUp",
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
