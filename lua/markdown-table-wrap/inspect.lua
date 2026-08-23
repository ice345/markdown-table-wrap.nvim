local M = {}

local function label(value)
  value = tostring(value or "source")
  return value:sub(1, 1):upper() .. value:sub(2)
end

local function display_path(context)
  if context.source_path and context.source_path ~= "" then
    return vim.fn.fnamemodify(context.source_path, ":~:.")
  end
  return "[No Name]"
end

local function mapping_text(value)
  if value == false or value == nil or value == "" then
    return "disabled"
  end
  if type(value) == "table" then
    return table.concat(value, ", ")
  end
  return tostring(value)
end

---@param context MarkdownTableWrapContext
---@return string[]
function M.format(context)
  local config = context.config or {}
  local table_text = "none"
  if context.table then
    table_text =
      string.format("%d-%d (%d columns)", context.table.start_lnum, context.table.end_lnum, context.table.columns)
  end
  local cell_text = context.cell and string.format("column %d: %s", context.cell.index, context.cell.text) or "none"
  local window_width = context.window.width or vim.o.columns
  local width_budget = math.max(1, math.floor(window_width * (tonumber(config.max_width_ratio) or 1)))

  return {
    string.format("MarkdownTableWrap %s", require("markdown-table-wrap").version or "unknown"),
    string.format("Mode: %s", label(context.mode)),
    string.format("Source: %s (buffer %d)", display_path(context), context.source_bufnr),
    string.format("View: buffer %d, window %s", context.view_bufnr, tostring(context.winid or "hidden")),
    string.format(
      "Cursor: source %d:%d, view %s:%s",
      context.cursor.source_lnum,
      context.cursor.source_col + 1,
      tostring(context.cursor.view_lnum or "hidden"),
      context.cursor.view_col and tostring(context.cursor.view_col + 1) or "hidden"
    ),
    "Table: " .. table_text,
    "Cell: " .. cell_text,
    string.format(
      "Window: %sx%s, width budget %d (ratio %.2f, columns %d-%d)",
      tostring(context.window.width or "hidden"),
      tostring(context.window.height or "hidden"),
      width_budget,
      tonumber(config.max_width_ratio) or 1,
      tonumber(config.min_col_width) or 1,
      tonumber(config.max_col_width) or 1
    ),
    string.format(
      "Cache: changedtick=%d rendered=%s paused=%s auto=%s enabled=%s entries=%d hits=%d misses=%d tokens=%d",
      context.cache.changedtick,
      tostring(context.cache.rendered),
      tostring(context.cache.paused),
      tostring(context.cache.auto_preview),
      tostring(context.cache.enabled),
      context.cache.entries or 0,
      context.cache.hits or 0,
      context.cache.misses or 0,
      context.cache.token_entries or 0
    ),
    string.format(
      "Discovery: requested=%s used=%s ranges=%d%s",
      tostring((context.discovery or {}).requested or "auto"),
      tostring((context.discovery or {}).used or "lua"),
      tonumber((context.discovery or {}).range_count) or 0,
      (context.discovery or {}).fallback_reason and (" (" .. context.discovery.fallback_reason .. ")") or ""
    ),
    string.format(
      "Options: preview=%s render_all=%s fit_to_window=%s inline=%s/%s",
      tostring(config.preview_mode),
      tostring(config.render_all),
      tostring(config.fit_to_window),
      tostring(config.inline_mode),
      tostring(config.inline_wrap_scope)
    ),
  }
end

---@param context MarkdownTableWrapContext
function M.notify(context)
  vim.notify(table.concat(M.format(context), "\n"), vim.log.levels.INFO, { title = "MarkdownTableWrap Inspect" })
end

local function help_lines(context)
  local mappings = (context.config.mappings or {})[context.mode] or {}
  if context.mode == "source" or context.mode == "inline" then
    mappings = (context.config.mappings or {}).reader or {}
  end
  if mappings == false then
    mappings = { enabled = false }
  end

  local lines = {
    "MarkdownTableWrap — " .. label(context.mode),
    "",
    "Common actions",
    "  :MarkdownTableEditSource       return to editable Source",
    "  :MarkdownTableOpen             open target under cursor",
    "  :MarkdownTableRefresh          refresh the active view",
    "  :MarkdownTableInspect          show diagnostic context",
    "  :MarkdownTableClosePreview     close the rendered view",
    "",
    "Configured view keys",
  }

  if mappings.enabled == false then
    table.insert(lines, "  local mappings: disabled (commands and <Plug> actions remain available)")
  else
    table.insert(lines, "  edit Source: " .. mapping_text(mappings.edit))
    table.insert(lines, "  open target: " .. mapping_text(mappings.open_link))
    table.insert(lines, "  close view:  " .. mapping_text(mappings.close))
    table.insert(lines, "  help:        " .. mapping_text(mappings.help))
  end
  table.insert(lines, "")
  table.insert(lines, "Press q or <Esc> to close this help.")
  return lines
end

---@param context MarkdownTableWrapContext
---@return integer, integer
function M.open_help(context)
  local lines = help_lines(context)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width, math.max(20, vim.o.columns - 4))
  local height = math.min(#lines, math.max(5, vim.o.lines - vim.o.cmdheight - 4))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown-table-wrap-help"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = context.config.border or "rounded",
    title = " MarkdownTableWrap Help ",
    title_pos = "center",
  })
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, silent = true, nowait = true })
  end
  return buf, win
end

return M
