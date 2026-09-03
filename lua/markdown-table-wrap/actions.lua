local M = {}

local actions = {}

local function notify(message, level)
  vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
end

local function context_for(opts)
  local context, err = require("markdown-table-wrap.context").resolve(opts or {})
  if not context then
    notify(err or "could not resolve the active Markdown Source", vim.log.levels.ERROR)
  end
  return context
end

local function leave_view(context, opts)
  opts = opts or {}
  local pause = opts.pause ~= false
  if not context or (context.mode ~= "reader" and context.mode ~= "float") then
    return context and context.source_bufnr or nil
  end

  local plugin = require("markdown-table-wrap")
  if context.mode == "float" then
    local source_winid = context.float and context.float.source_winid or nil
    local source_bufnr = context.source_bufnr
    local was_paused = plugin.state.paused_buffers[source_bufnr] == true
    plugin.close_preview()
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    end
    if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
      if pause then
        plugin.pause_buffer(source_bufnr)
      else
        plugin.state.paused_buffers[source_bufnr] = was_paused or nil
      end
    end
    return vim.api.nvim_get_current_buf() == context.source_bufnr and context.source_bufnr or nil
  end

  local source_bufnr = require("markdown-table-wrap.reader").close(context.view_bufnr)
  if source_bufnr and pause then
    plugin.pause_buffer(source_bufnr)
  end
  return source_bufnr
end

actions.toggle_reader = function(context)
  if context.mode == "float" and not leave_view(context) then
    return false
  end
  return require("markdown-table-wrap").toggle_reader()
end

actions.toggle_inline = function(context)
  if context.mode == "float" and not leave_view(context) then
    return false
  end
  return require("markdown-table-wrap").toggle_inline()
end

actions.edit_source = function(context)
  if context.mode == "reader" or context.mode == "float" then
    return leave_view(context) ~= nil
  end
  require("markdown-table-wrap").close_preview()
  return true
end

actions.close = function()
  require("markdown-table-wrap").close_preview()
  return true
end

actions.refresh = function(context)
  if context.mode == "reader" then
    return require("markdown-table-wrap.reader").refresh(context.view_bufnr)
  elseif context.mode == "float" then
    local plugin = require("markdown-table-wrap")
    local was_paused = plugin.state.paused_buffers[context.source_bufnr]
    if not leave_view(context) then
      return false
    end
    plugin.state.paused_buffers[context.source_bufnr] = was_paused
    return plugin.float_preview() ~= false
  end
  require("markdown-table-wrap").refresh_auto({ bufnr = context.source_bufnr, force = true })
  return true
end

actions.scroll_down = function(_, opts)
  require("markdown-table-wrap").scroll_view(math.max(1, tonumber(opts.count) or vim.v.count1))
  return true
end

actions.scroll_up = function(_, opts)
  require("markdown-table-wrap").scroll_view(-math.max(1, tonumber(opts.count) or vim.v.count1))
  return true
end

actions.scroll_top = function()
  require("markdown-table-wrap").scroll_view_to("top")
  return true
end

actions.scroll_bottom = function()
  require("markdown-table-wrap").scroll_view_to("bottom")
  return true
end

actions.viewport_left = function(_, opts)
  return require("markdown-table-wrap").shift_wide_table_viewport(-(tonumber(opts.count) or 1))
end

actions.viewport_right = function(_, opts)
  return require("markdown-table-wrap").shift_wide_table_viewport(tonumber(opts.count) or 1)
end

local function buffer_command(context, command)
  if (context.mode == "reader" or context.mode == "float") and not leave_view(context) then
    return false
  end
  local ok, err = pcall(vim.cmd, command)
  if not ok then
    notify("buffer navigation failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

actions.next_buffer = function(context)
  return buffer_command(context, "bnext")
end

actions.previous_buffer = function(context)
  return buffer_command(context, "bprevious")
end

actions.alternate_buffer = function(context)
  local target = nil
  if context.mode == "reader" then
    local summary = require("markdown-table-wrap.reader").summary(context.view_bufnr)
    target = summary and summary.source_alt_bufnr or nil
    if not leave_view(context) then
      return false
    end
  elseif context.mode == "float" then
    target = context.float and context.float.source_alt_bufnr or nil
    if not leave_view(context) then
      return false
    end
  end

  if target and vim.api.nvim_buf_is_valid(target) and vim.fn.buflisted(target) == 1 then
    vim.api.nvim_win_set_buf(0, target)
    return true
  end
  return buffer_command({ mode = "source" }, "buffer #")
end

actions.select_buffer = function(context, opts)
  local target = tonumber(opts.target_bufnr)
  if not target or not vim.api.nvim_buf_is_valid(target) then
    notify("the requested buffer is not valid", vim.log.levels.ERROR)
    return false
  end
  if (context.mode == "reader" or context.mode == "float") and not leave_view(context) then
    return false
  end
  vim.api.nvim_win_set_buf(0, target)
  return true
end

actions.split_source = function(context)
  if (context.mode == "reader" or context.mode == "float") and not leave_view(context) then
    return false
  end
  vim.cmd("split")
  return true
end

actions.vsplit_source = function(context)
  if (context.mode == "reader" or context.mode == "float") and not leave_view(context) then
    return false
  end
  vim.cmd("vsplit")
  return true
end

actions.tab_source = function(context)
  if (context.mode == "reader" or context.mode == "float") and not leave_view(context) then
    return false
  end
  vim.cmd("tab split")
  return true
end

actions.open = function(context, opts)
  return require("markdown-table-wrap.links").open_at_context(
    context,
    vim.tbl_extend("force", {}, opts, { strategy = "edit" })
  )
end

actions.open_split = function(context, opts)
  return require("markdown-table-wrap.links").open_at_context(
    context,
    vim.tbl_extend("force", {}, opts, { strategy = "split" })
  )
end

actions.open_vsplit = function(context, opts)
  return require("markdown-table-wrap.links").open_at_context(
    context,
    vim.tbl_extend("force", {}, opts, { strategy = "vsplit" })
  )
end

actions.open_tab = function(context, opts)
  return require("markdown-table-wrap.links").open_at_context(
    context,
    vim.tbl_extend("force", {}, opts, { strategy = "tab" })
  )
end

actions.inspect = function(context)
  require("markdown-table-wrap.inspect").notify(context)
  return true
end

actions.help = function(context)
  require("markdown-table-wrap.inspect").open_help(context)
  return true
end

actions.copy_cell = function(context, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { context = context })
  return require("markdown-table-wrap.export").cell(opts)
end

actions.put_cell = function(context, opts)
  if context.mode ~= "reader" then
    notify("cell put is available only in Reader mode", vim.log.levels.WARN)
    return false
  end
  opts = opts or {}
  return require("markdown-table-wrap.cell_ops").put(context.view_bufnr, {
    register = opts.register or vim.v.register,
    count = opts.count or vim.v.count,
  })
end

actions.copy_table = function(context, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { context = context })
  return require("markdown-table-wrap.export").table(opts)
end

actions.export_tsv = function(context, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { context = context, format = "tsv" })
  return require("markdown-table-wrap.export").export(opts)
end

actions.export_csv = function(context, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { context = context, format = "csv" })
  return require("markdown-table-wrap.export").export(opts)
end

local function table_edit_action(name, context, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { context = context })
  return require("markdown-table-wrap.table_edit")[name](opts)
end

for _, name in ipairs({
  "format",
  "add_row",
  "delete_row",
  "move_row_up",
  "move_row_down",
  "add_column",
  "delete_column",
  "move_column_left",
  "move_column_right",
  "toggle_alignment",
  "open_cell_popup",
}) do
  actions[name .. "_table"] = function(context, opts)
    return table_edit_action(name, context, opts)
  end
end

---@param fn function
---@return any
function M.with_source(fn)
  if type(fn) ~= "function" then
    error("MarkdownTableWrap: with_source requires a function", 2)
  end

  local context = require("markdown-table-wrap.context").resolve({})
  if not context or (context.mode ~= "reader" and context.mode ~= "float") then
    return fn()
  end

  local plugin = require("markdown-table-wrap")
  local source_bufnr = context.source_bufnr
  local was_paused = plugin.state.paused_buffers[source_bufnr] == true
  plugin.state.paused_buffers[source_bufnr] = true
  plugin.state.refresh_tokens[source_bufnr] = (plugin.state.refresh_tokens[source_bufnr] or 0) + 1
  leave_view(context, { pause = false })

  local ok, result = pcall(fn)
  if was_paused then
    plugin.state.paused_buffers[source_bufnr] = true
  else
    plugin.state.paused_buffers[source_bufnr] = nil
  end

  if
    not was_paused
    and vim.api.nvim_buf_is_valid(source_bufnr)
    and vim.api.nvim_get_current_buf() == source_bufnr
  then
    plugin.schedule_refresh({ bufnr = source_bufnr, silent = true })
  end

  if not ok then
    error(result, 0)
  end
  return result
end

---@param command string
---@return any
function M.source_command(command)
  command = type(command) == "string" and vim.trim(command) or ""
  if command == "" then
    notify("source_command requires an Ex command", vim.log.levels.ERROR)
    return false
  end
  return M.with_source(function()
    vim.cmd(command)
  end)
end

function M.run(name, opts)
  opts = opts or {}
  local action = actions[name]
  if not action then
    notify("unknown action " .. vim.inspect(name), vim.log.levels.ERROR)
    return false
  end

  local context = opts.context or context_for(opts)
  if not context then
    return false
  end
  return action(context, opts) ~= false
end

function M.passthrough(reader_bufnr, lhs, spec)
  local reader = require("markdown-table-wrap.reader")
  local context = context_for({ bufnr = reader_bufnr })
  if not context then
    return false
  end

  if type(spec) == "string" and actions[spec] then
    return M.run(spec, { context = context })
  end

  spec = type(spec) == "table" and spec or {}
  if type(spec.action) == "string" then
    return M.run(spec.action, vim.tbl_extend("force", {}, spec, { context = context }))
  end

  local mapping = reader.mapping_fallback(reader_bufnr, "passthrough", lhs)
  local policy = spec.policy or "leave"
  if policy == "leave" then
    if not leave_view(context) then
      return false
    end
    return require("markdown-table-wrap.mappings").invoke(mapping, { context_bufnr = context.source_bufnr })
  elseif policy == "source" then
    return require("markdown-table-wrap.mappings").invoke(mapping, {
      context_bufnr = context.source_bufnr,
      cursor = { context.cursor.source_lnum, context.cursor.source_col },
    })
  end
  return require("markdown-table-wrap.mappings").invoke(mapping)
end

function M.exists(name)
  return actions[name] ~= nil
end

function M.names()
  local names = vim.tbl_keys(actions)
  table.sort(names)
  return names
end

return M
