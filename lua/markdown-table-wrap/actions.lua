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

local function leave_view(context)
  if not context or (context.mode ~= "reader" and context.mode ~= "float") then
    return context and context.source_bufnr or nil
  end

  if context.mode == "float" then
    local source_winid = context.float and context.float.source_winid or nil
    require("markdown-table-wrap").close_preview()
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    end
    return vim.api.nvim_get_current_buf() == context.source_bufnr and context.source_bufnr or nil
  end

  local source_bufnr = require("markdown-table-wrap.reader").close(context.view_bufnr)
  if source_bufnr then
    require("markdown-table-wrap").pause_buffer(source_bufnr)
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
    local state = require("markdown-table-wrap.reader").get_state(context.view_bufnr)
    target = state and state.source_alt_bufnr or nil
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
  local state = reader.get_state(reader_bufnr)
  local context = context_for({ bufnr = reader_bufnr })
  if not state or not context then
    return false
  end

  if type(spec) == "string" and actions[spec] then
    return M.run(spec, { context = context })
  end

  spec = type(spec) == "table" and spec or {}
  if type(spec.action) == "string" then
    return M.run(spec.action, vim.tbl_extend("force", {}, spec, { context = context }))
  end

  local mapping = (state.passthrough_fallbacks or {})[lhs]
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
