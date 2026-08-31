local M = {}

local function start(name)
  if vim.health and vim.health.start then
    vim.health.start(name)
  else
    vim.health.report_start(name)
  end
end

local function ok(message)
  if vim.health and vim.health.ok then
    vim.health.ok(message)
  else
    vim.health.report_ok(message)
  end
end

local function warn(message)
  if vim.health and vim.health.warn then
    vim.health.warn(message)
  else
    vim.health.report_warn(message)
  end
end

---@return { level: "ok"|"warn", message: string }[]
function M.collect()
  local plugin = require("markdown-table-wrap")
  local report = {}
  local function add(level, message)
    table.insert(report, { level = level, message = message })
  end

  add("ok", "Version " .. (plugin.version or "unknown"))
  if vim.fn.has("nvim-0.10") == 1 then
    add("ok", "Neovim >= 0.10")
  else
    add("warn", "Neovim 0.10+ is required")
  end

  local modules = {
    "markdown-table-wrap",
    "markdown-table-wrap.actions",
    "markdown-table-wrap.cache",
    "markdown-table-wrap.commands",
    "markdown-table-wrap.config",
    "markdown-table-wrap.context",
    "markdown-table-wrap.discovery",
    "markdown-table-wrap.events",
    "markdown-table-wrap.inline",
    "markdown-table-wrap.inspect",
    "markdown-table-wrap.links",
    "markdown-table-wrap.mappings",
    "markdown-table-wrap.markdown",
    "markdown-table-wrap.parser",
    "markdown-table-wrap.reader",
    "markdown-table-wrap.render",
    "markdown-table-wrap.theme",
    "markdown-table-wrap.wrap",
  }
  for _, module in ipairs(modules) do
    local loaded, err = pcall(require, module)
    if loaded then
      add("ok", "Loaded " .. module)
    else
      add("warn", "Could not load " .. module .. ": " .. tostring(err))
    end
  end

  local theme = require("markdown-table-wrap.theme")
  local preset = plugin.config.highlight_preset
  if vim.tbl_contains(theme.presets(), preset) or type((plugin.config.themes or {})[preset]) == "table" then
    add("ok", "Highlight preset: " .. tostring(preset))
  else
    add("warn", "Highlight preset is unresolved: " .. tostring(preset))
  end

  local context, context_err = require("markdown-table-wrap.context").resolve({})
  if context then
    add(
      "ok",
      string.format(
        "Active context: %s view buffer %d -> Source buffer %d (%s)",
        context.mode,
        context.view_bufnr,
        context.source_bufnr,
        context.source_path or "[No Name]"
      )
    )
  else
    add("ok", "No active MarkdownTableWrap context: " .. tostring(context_err))
  end

  local resolver = (plugin.config.link or {}).resolver
  if resolver == nil then
    add("ok", "Link resolver: built-in Source-aware resolver")
  elseif type(resolver) == "function" then
    add("ok", "Link resolver: custom callback")
  else
    add("warn", "Link resolver must be a function")
  end

  local reader_mappings = (plugin.config.mappings or {}).reader
  if reader_mappings and reader_mappings.enabled == false then
    add("ok", "Reader mappings disabled; commands and <Plug> actions remain available")
  elseif type(reader_mappings) == "table" then
    local exit = reader_mappings.edit or reader_mappings.close
    if exit and exit ~= false then
      add("ok", "Reader exit/edit mapping is configured: " .. tostring(exit))
    else
      add("warn", "Reader has no local exit/edit key; use :MarkdownTableEditSource or :MarkdownTableClosePreview")
    end
  else
    add("warn", "Reader mapping configuration is unavailable")
  end

  if plugin.config.map_gx then
    add("ok", "Source gx proxy enabled; prior mapping is captured and restored")
  else
    add("ok", "Source gx proxy disabled; use :MarkdownTableOpen or a <Plug> mapping")
  end

  local discovery = require("markdown-table-wrap.discovery").status(vim.api.nvim_get_current_buf())
  add(
    "ok",
    string.format(
      "Discovery backend: requested=%s used=%s%s",
      discovery.requested,
      discovery.used,
      discovery.fallback_reason and (" (" .. discovery.fallback_reason .. ")") or ""
    )
  )
  local cache = require("markdown-table-wrap.cache").inspect(vim.api.nvim_get_current_buf())
  add("ok", string.format("Cache: enabled=%s entries=%d", tostring(cache.enabled), cache.entries))

  local render_markdown_loaded = package.loaded["render-markdown"] ~= nil
    or package.loaded["render-markdown.core"] ~= nil
  if render_markdown_loaded then
    add("warn", "render-markdown.nvim is loaded; disable its pipe_table renderer to avoid overlapping table views")
  else
    add("ok", "No loaded render-markdown.nvim table renderer was detected")
  end

  return report
end

function M.check()
  start("markdown-table-wrap.nvim")
  for _, item in ipairs(M.collect()) do
    if item.level == "warn" then
      warn(item.message)
    else
      ok(item.message)
    end
  end
end

return M
