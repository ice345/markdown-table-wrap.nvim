local M = {}

local presets = {
  tokyonight = {
    border = { fg = "#3d59a1" },
    inline = { fg = "#c0caf5" },
    source = { link = "Comment" },
    header = { fg = "#7aa2f7", bold = true },
    code = { fg = "#9ece6a" },
    link = { fg = "#7dcfff", underline = true },
    bold = { fg = "#e0af68", bold = true },
    italic = { fg = "#7aa2f7", italic = true },
    strike = { fg = "#f7768e", strikethrough = true },
    mark = { fg = "#1a1b26", bg = "#e0af68" },
    wiki_link = { fg = "#bb9af7", underline = true },
    image = { fg = "#73daca" },
    blank = { link = "Normal" },
  },
  catppuccin = {
    border = { fg = "#89b4fa" },
    inline = { fg = "#cdd6f4" },
    source = { link = "Comment" },
    header = { fg = "#89b4fa", bold = true },
    code = { fg = "#a6e3a1" },
    link = { fg = "#89dceb", underline = true },
    bold = { fg = "#f9e2af", bold = true },
    italic = { fg = "#cba6f7", italic = true },
    strike = { fg = "#f38ba8", strikethrough = true },
    mark = { fg = "#1e1e2e", bg = "#f9e2af" },
    wiki_link = { fg = "#cba6f7", underline = true },
    image = { fg = "#94e2d5" },
    blank = { link = "Normal" },
  },
  default = {
    border = { link = "FloatBorder" },
    inline = { link = "Normal" },
    source = { link = "Comment" },
    header = { link = "Title" },
    code = { link = "String" },
    link = { link = "Underlined" },
    bold = { bold = true },
    italic = { italic = true },
    strike = { strikethrough = true },
    mark = { link = "Search" },
    wiki_link = { link = "Underlined" },
    image = { link = "Special" },
    blank = { link = "Normal" },
  },
  render_markdown = {
    border = { link = "RenderMarkdownTableRow" },
    inline = { link = "RenderMarkdownTableRow" },
    source = { link = "Comment" },
    header = { link = "RenderMarkdownTableHead" },
    code = { link = "RenderMarkdownCodeInline" },
    link = { link = "RenderMarkdownLink" },
    bold = { fg = "#e0af68", bold = true },
    italic = { fg = "#7aa2f7", italic = true },
    strike = { fg = "#f7768e", strikethrough = true },
    mark = { link = "RenderMarkdownInlineHighlight" },
    wiki_link = { link = "RenderMarkdownWikiLink" },
    image = { link = "RenderMarkdownImage" },
    blank = { link = "Normal" },
  },
}

local groups = {
  border = "MarkdownTableWrapBorder",
  inline = "MarkdownTableWrapInline",
  source = "MarkdownTableWrapSource",
  header = "MarkdownTableWrapHeader",
  code = "MarkdownTableWrapCode",
  link = "MarkdownTableWrapLink",
  bold = "MarkdownTableWrapBold",
  italic = "MarkdownTableWrapItalic",
  strike = "MarkdownTableWrapStrike",
  mark = "MarkdownTableWrapMark",
  wiki_link = "MarkdownTableWrapWikiLink",
  image = "MarkdownTableWrapImage",
  blank = "MarkdownTableWrapBlank",
}

local function detect_preset()
  local colors_name = (vim.g.colors_name or ""):lower()

  if colors_name:find("catppuccin", 1, true) then
    return "catppuccin"
  elseif colors_name:find("tokyonight", 1, true) then
    return "tokyonight"
  end

  return "default"
end

local function normalize_spec(spec)
  if type(spec) ~= "table" then
    return { link = "Normal" }
  end

  if spec.link and vim.fn.hlexists(spec.link) == 0 then
    local fallback = presets.default
    for key, group in pairs(groups) do
      if group == spec.link then
        return fallback[key] or { link = "Normal" }
      end
    end
    return { link = "Normal" }
  end
  return spec
end

local function load_theme_file(config, preset_name)
  local theme_dir = config.theme_dir
  if not theme_dir or preset_name == "auto" then
    return nil
  end

  local path = vim.fn.fnamemodify(theme_dir .. "/" .. preset_name .. ".lua", ":p")
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, theme = pcall(dofile, path)
  if ok and type(theme) == "table" then
    return theme
  end

  vim.notify("MarkdownTableWrap: failed to load theme " .. path, vim.log.levels.WARN)
  return nil
end

function M.apply(config)
  config = config or {}
  local preset_name = config.highlight_preset or "tokyonight"
  if preset_name == "auto" then
    preset_name = detect_preset()
  end
  local custom_theme = (config.themes or {})[preset_name]
  if type(custom_theme) ~= "table" then
    custom_theme = load_theme_file(config, preset_name)
  end
  local preset = vim.deepcopy(custom_theme or presets[preset_name] or presets.default)
  local overrides = config.highlights or {}

  for key, group in pairs(groups) do
    local base = type(preset[key]) == "table" and preset[key] or {}
    local override = type(overrides[key]) == "table" and overrides[key] or {}
    local spec = vim.tbl_deep_extend("force", base, override)
    vim.api.nvim_set_hl(0, group, normalize_spec(spec))
  end
end

function M.groups()
  return groups
end

function M.presets()
  local names = vim.tbl_keys(presets)
  table.insert(names, "auto")
  table.sort(names)
  return names
end

return M
