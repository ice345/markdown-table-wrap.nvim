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

function M.check()
  start("markdown-table-wrap.nvim")

  local plugin = require("markdown-table-wrap")
  ok("Version " .. (plugin.version or "unknown"))

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    warn("Neovim 0.10+ is required")
  end

  local modules = {
    "markdown-table-wrap",
    "markdown-table-wrap.parser",
    "markdown-table-wrap.markdown",
    "markdown-table-wrap.wrap",
    "markdown-table-wrap.render",
    "markdown-table-wrap.inline",
    "markdown-table-wrap.theme",
  }

  for _, module in ipairs(modules) do
    local loaded = pcall(require, module)
    if loaded then
      ok("Loaded " .. module)
    else
      warn("Could not load " .. module)
    end
  end

  local theme = require("markdown-table-wrap.theme")
  ok("Available highlight presets: " .. table.concat(theme.presets(), ", "))

  local render_markdown_loaded = package.loaded["render-markdown"] ~= nil
  if render_markdown_loaded then
    warn("render-markdown.nvim is loaded. Disable its pipe_table renderer to avoid table conflicts.")
  else
    ok("render-markdown.nvim is not currently loaded")
  end
end

return M
