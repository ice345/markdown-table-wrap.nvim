local M = {}

local defaults = {
  max_width_ratio = 0.9,
  min_col_width = 8,
  max_col_width = 50,
  fit_to_window = true,
  border = "rounded",
  use_unicode_border = true,
  table_border = "rounded",
  row_separator = true,
  preview_mode = "reader",
  inline_mode = "replace",
  inline_position = "above",
  dim_source = true,
  auto_preview = true,
  render_all = true,
  auto_preview_in_insert = false,
  clear_on_cursor_leave = true,
  clear_on_insert = true,
  clear_on_visual = true,
  debounce_ms = 80,
  discovery = {
    backend = "auto",
  },
  cache = {
    enabled = true,
  },
  overlay_priority = 10000,
  overlay_fill = true,
  inline_virtual_text = "overlay",
  inline_disable_wrap = true,
  inline_wrap_scope = "cursor",
  inline_viewport_scrolling = false,
  wide_table = {
    mode = "wrap",
    viewport = {
      start_column = 1,
      column_count = nil,
      marker = "…",
    },
    columns = {},
  },
  reader = {
    auto_open = "has_table",
    wrap = true,
    linebreak = false,
    breakindent = true,
    conceallevel = 2,
    concealcursor = "nvc",
    sticky_header = false,
  },
  highlight_preset = "default",
  theme_dir = nil,
  themes = {},
  extra_filetypes = {},
  highlights = {},
  map_gx = false,
  mappings = {
    reader = {
      enabled = true,
      close = "q",
      edit = "e",
      open_link = "gx",
      help = false,
      copy_cell = false,
      copy_table = false,
      insert = { "i", "a", "I", "A", "o", "O" },
      passthrough = {},
      cell = {
        enabled = true,
        yank = "yic",
        visual = "vic",
        delete = "dic",
        change = "cic",
        put = false,
        change_operator = "c",
        repeat_change = ".",
      },
    },
    float = {
      enabled = true,
      close = { "q", "<Esc>" },
      open_link = "gx",
      help = false,
    },
  },
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
}

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.resolve(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  config.max_width_ratio = tonumber(config.max_width_ratio) or defaults.max_width_ratio
  config.min_col_width = math.max(1, tonumber(config.min_col_width) or defaults.min_col_width)
  config.max_col_width = math.max(config.min_col_width, tonumber(config.max_col_width) or defaults.max_col_width)
  config.debounce_ms = math.max(0, tonumber(config.debounce_ms) or defaults.debounce_ms)
  config.overlay_priority = math.max(1, tonumber(config.overlay_priority) or defaults.overlay_priority)
  config.max_width_ratio = math.max(0.1, math.min(1, config.max_width_ratio))
  config.render_all = config.render_all ~= false
  config.overlay_fill = config.overlay_fill ~= false
  config.fit_to_window = config.fit_to_window ~= false
  config.clear_on_visual = config.clear_on_visual ~= false
  config.inline_disable_wrap = config.inline_disable_wrap ~= false
  config.inline_viewport_scrolling = config.inline_viewport_scrolling ~= false
  config.map_gx = config.map_gx == true

  if type(config.discovery) ~= "table" then
    config.discovery = vim.deepcopy(defaults.discovery)
  end
  if not vim.tbl_contains({ "auto", "lua", "treesitter" }, config.discovery.backend) then
    config.discovery.backend = defaults.discovery.backend
  end
  if type(config.cache) ~= "table" then
    config.cache = vim.deepcopy(defaults.cache)
  end
  config.cache.enabled = config.cache.enabled ~= false

  if type(config.mappings) ~= "table" then
    config.mappings = vim.deepcopy(defaults.mappings)
  end
  for _, view in ipairs({ "reader", "float" }) do
    local value = config.mappings[view]
    if value == false then
      config.mappings[view] = { enabled = false }
    elseif type(value) ~= "table" then
      config.mappings[view] = vim.deepcopy(defaults.mappings[view])
    else
      config.mappings[view] = vim.tbl_deep_extend("force", vim.deepcopy(defaults.mappings[view]), value)
      config.mappings[view].enabled = config.mappings[view].enabled ~= false
    end
  end
  if config.mappings.reader.insert == false then
    config.mappings.reader.insert = {}
  elseif type(config.mappings.reader.insert) ~= "table" then
    config.mappings.reader.insert = vim.deepcopy(defaults.mappings.reader.insert)
  end
  if type(config.mappings.reader.passthrough) ~= "table" then
    config.mappings.reader.passthrough = {}
  end
  if config.mappings.reader.cell == false then
    config.mappings.reader.cell = { enabled = false }
  elseif type(config.mappings.reader.cell) ~= "table" then
    config.mappings.reader.cell = vim.deepcopy(defaults.mappings.reader.cell)
  else
    config.mappings.reader.cell =
      vim.tbl_deep_extend("force", vim.deepcopy(defaults.mappings.reader.cell), config.mappings.reader.cell)
    config.mappings.reader.cell.enabled = config.mappings.reader.cell.enabled ~= false
  end
  if
    config.mappings.float.close ~= false
    and type(config.mappings.float.close) ~= "table"
    and type(config.mappings.float.close) ~= "string"
  then
    config.mappings.float.close = vim.deepcopy(defaults.mappings.float.close)
  end

  if not vim.tbl_contains({ "always", "cursor", "never" }, config.inline_wrap_scope) then
    config.inline_wrap_scope = defaults.inline_wrap_scope
  end

  if type(config.extra_filetypes) ~= "table" or #config.extra_filetypes == 0 then
    config.extra_filetypes = {}
  else
    local valid = true
    for _, value in ipairs(config.extra_filetypes) do
      if type(value) ~= "string" then
        valid = false
        break
      end
    end
    if not valid then
      config.extra_filetypes = {}
    end
  end

  if type(config.reader) ~= "table" then
    config.reader = vim.deepcopy(defaults.reader)
  end
  if not vim.tbl_contains({ "has_table", "always" }, config.reader.auto_open) then
    config.reader.auto_open = defaults.reader.auto_open
  end
  config.reader.wrap = config.reader.wrap ~= false
  config.reader.linebreak = config.reader.linebreak == true
  config.reader.breakindent = config.reader.breakindent ~= false
  config.reader.conceallevel =
    math.floor(math.max(0, math.min(3, tonumber(config.reader.conceallevel) or defaults.reader.conceallevel)))
  if type(config.reader.concealcursor) ~= "string" or config.reader.concealcursor:match("^[nvic]*$") == nil then
    config.reader.concealcursor = defaults.reader.concealcursor
  end
  config.reader.sticky_header = config.reader.sticky_header == true

  if type(config.wide_table) ~= "table" then
    config.wide_table = vim.deepcopy(defaults.wide_table)
  else
    config.wide_table = vim.tbl_deep_extend("force", vim.deepcopy(defaults.wide_table), config.wide_table)
  end
  if not vim.tbl_contains({ "wrap", "viewport" }, config.wide_table.mode) then
    config.wide_table.mode = defaults.wide_table.mode
  end
  if type(config.wide_table.viewport) ~= "table" then
    config.wide_table.viewport = vim.deepcopy(defaults.wide_table.viewport)
  else
    config.wide_table.viewport =
      vim.tbl_deep_extend("force", vim.deepcopy(defaults.wide_table.viewport), config.wide_table.viewport)
  end
  config.wide_table.viewport.start_column = math.max(
    1,
    math.floor(tonumber(config.wide_table.viewport.start_column) or defaults.wide_table.viewport.start_column)
  )
  if config.wide_table.viewport.column_count ~= nil then
    local count = tonumber(config.wide_table.viewport.column_count)
    config.wide_table.viewport.column_count = count and math.max(1, math.floor(count)) or nil
  end
  if type(config.wide_table.viewport.marker) ~= "string" or config.wide_table.viewport.marker == "" then
    config.wide_table.viewport.marker = defaults.wide_table.viewport.marker
  end
  if type(config.wide_table.columns) ~= "table" then
    config.wide_table.columns = {}
  end
  for index, rule in pairs(config.wide_table.columns) do
    if type(rule) ~= "table" or tonumber(index) == nil then
      config.wide_table.columns[index] = nil
    else
      if rule.width ~= nil then
        rule.width = math.max(1, math.floor(tonumber(rule.width) or 1))
      end
      if rule.min ~= nil then
        rule.min = math.max(1, math.floor(tonumber(rule.min) or 1))
      end
      if rule.max ~= nil then
        rule.max = math.max(rule.min or 1, math.floor(tonumber(rule.max) or (rule.min or 1)))
      end
      if rule.min and rule.max and rule.max < rule.min then
        rule.max = rule.min
      end
      if rule.weight ~= nil then
        rule.weight = math.max(0, tonumber(rule.weight) or 1)
      end
      if rule.priority ~= nil then
        rule.priority = math.max(0, math.floor(tonumber(rule.priority) or 0))
      end
    end
  end

  if type(config.themes) ~= "table" then
    config.themes = {}
  end
  if type(config.highlights) ~= "table" then
    config.highlights = {}
  end
  if type(config.theme_dir) ~= "string" then
    config.theme_dir = nil
  end

  if type(config.link) ~= "table" then
    config.link = vim.deepcopy(defaults.link)
  end
  config.link.icon = type(config.link.icon) == "string" and config.link.icon or defaults.link.icon
  config.link.image = type(config.link.image) == "string" and config.link.image or defaults.link.image
  if type(config.link.wiki) ~= "table" then
    config.link.wiki = vim.deepcopy(defaults.link.wiki)
  end
  if type(config.link.custom) ~= "table" then
    config.link.custom = vim.deepcopy(defaults.link.custom)
  end
  if config.link.resolver ~= nil and type(config.link.resolver) ~= "function" then
    config.link.resolver = nil
  end

  if config.inline_virtual_text ~= "overlay" and config.inline_virtual_text ~= "win_col" then
    config.inline_virtual_text = defaults.inline_virtual_text
  end

  if config.preview_mode ~= "inline" and config.preview_mode ~= "float" and config.preview_mode ~= "reader" then
    config.preview_mode = defaults.preview_mode
  end

  if config.inline_mode ~= "replace" and config.inline_mode ~= "insert" then
    config.inline_mode = defaults.inline_mode
  end

  if config.inline_position ~= "above" and config.inline_position ~= "below" then
    config.inline_position = defaults.inline_position
  end

  if config.table_border ~= "rounded" and config.table_border ~= "single" then
    config.table_border = defaults.table_border
  end

  local preset_name = config.highlight_preset
  local builtin_preset = false
  for _, preset in ipairs(require("markdown-table-wrap.theme").presets()) do
    if preset == preset_name then
      builtin_preset = true
      break
    end
  end
  local inline_custom = type(config.themes[preset_name]) == "table"
  local file_custom = type(config.theme_dir) == "string"
  if
    type(preset_name) ~= "string"
    or preset_name == ""
    or (not builtin_preset and not inline_custom and not file_custom)
  then
    config.highlight_preset = defaults.highlight_preset
  end

  return config
end

return M
