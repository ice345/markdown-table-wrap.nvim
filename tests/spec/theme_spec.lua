local h = require("tests.helpers")

h.test("theme presets and overrides", function()
  local theme = require("markdown-table-wrap.theme")
  theme.apply({
    highlight_preset = "tokyonight",
    highlights = {
      code = { fg = "#ffffff" },
    },
  })

  local code = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapCode" })
  h.assert_eq("theme override code fg", code.fg, tonumber("ffffff", 16))

  local presets = {}
  for _, preset in ipairs(theme.presets()) do
    presets[preset] = true
  end
  h.assert_true("tokyonight preset", presets.tokyonight)
  h.assert_true("catppuccin preset", presets.catppuccin)
  h.assert_true("default preset", presets.default)
  h.assert_true("render_markdown preset", presets.render_markdown)
  h.assert_true("auto preset", presets.auto)

  theme.apply({ highlight_preset = "catppuccin" })
  local header = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapHeader" })
  h.assert_eq("catppuccin header fg", header.fg, tonumber("89b4fa", 16))

  local previous_colors_name = vim.g.colors_name
  vim.g.colors_name = "catppuccin-mocha"
  theme.apply({ highlight_preset = "auto" })
  local auto_code = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapCode" })
  h.assert_eq("auto detects catppuccin", auto_code.fg, tonumber("a6e3a1", 16))
  vim.g.colors_name = previous_colors_name

  theme.apply({
    highlight_preset = "custom_test",
    themes = {
      custom_test = {
        border = { fg = "#111111" },
        inline = { fg = "#222222" },
        source = { fg = "#333333" },
        header = { fg = "#444444" },
        code = { fg = "#555555" },
        link = { fg = "#666666" },
        bold = { fg = "#777777" },
        italic = { fg = "#888888" },
        strike = { fg = "#999999" },
        mark = { fg = "#aaaaaa" },
        wiki_link = { fg = "#bbbbbb" },
        image = { fg = "#cccccc" },
        blank = { fg = "#dddddd" },
      },
    },
  })
  local mark = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapMark" })
  h.assert_eq("custom theme table", mark.fg, tonumber("aaaaaa", 16))

  local theme_dir = vim.fn.tempname()
  vim.fn.mkdir(theme_dir, "p")
  vim.fn.writefile({
    "return {",
    "  border = { fg = '#010101' },",
    "  inline = { fg = '#020202' },",
    "  source = { fg = '#030303' },",
    "  header = { fg = '#040404' },",
    "  code = { fg = '#050505' },",
    "  link = { fg = '#060606' },",
    "  bold = { fg = '#070707' },",
    "  italic = { fg = '#080808' },",
    "  strike = { fg = '#090909' },",
    "  mark = { fg = '#0a0a0a' },",
    "  wiki_link = { fg = '#0b0b0b' },",
    "  image = { fg = '#0c0c0c' },",
    "  blank = { fg = '#0d0d0d' },",
    "}",
  }, theme_dir .. "/file_theme.lua")
  theme.apply({ highlight_preset = "file_theme", theme_dir = theme_dir })
  local image = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapImage" })
  h.assert_eq("theme loaded from directory", image.fg, tonumber("0c0c0c", 16))
end)
