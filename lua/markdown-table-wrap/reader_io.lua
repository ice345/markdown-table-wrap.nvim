local M = {}
local prefix = "markdown-table-wrap://reader/"

local function encode(path)
  return (path:gsub("[^%w%-%._~]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

function M.name(view, source)
  local path = vim.api.nvim_buf_get_name(source)
  return prefix .. "v1/" .. view .. "/" .. (path == "" and "-" or encode(path))
end

function M.rename(view, source)
  local name = M.name(view, source)
  if vim.api.nvim_buf_get_name(view) ~= name then
    vim.api.nvim_buf_set_name(view, name)
  end
  vim.b[view].markdown_table_wrap_uri = name
end

function M.write(view, opts)
  opts = opts or {}
  local reader = require("markdown-table-wrap.reader")
  local source = reader.source_bufnr(view)
  if not source or not vim.api.nvim_buf_is_loaded(source) then
    return false, "the backing Source buffer is no longer available"
  end

  local uri = vim.b[view].markdown_table_wrap_uri
  local renamed = uri and vim.api.nvim_buf_get_name(view) ~= uri
  local path = opts.file
  if not path or path == "" or path == uri then
    path = nil
  elseif path:find("[%z\1-\31\127]") or path:sub(1, #prefix) == prefix then
    return false, "invalid Source write path"
  end
  if not path and vim.api.nvim_buf_get_name(source) == "" then
    return false, "the Source buffer has no file name; use :write {path}"
  end

  local range
  local tick = vim.api.nvim_buf_get_changedtick(source)
  if opts.partial then
    if tick ~= reader.source_changedtick(view) then
      return false, "Source changed since Reader was rendered; refresh before writing a range"
    end
    range = reader.source_range(view, opts.first, opts.last)
    if not range then
      return false, "the selected Reader range has no physical Source range"
    end
  end

  -- :saveas renames the current buffer before BufWriteCmd. Release its real
  -- target name first so native :saveas can rename the canonical Source.
  if renamed then
    vim.api.nvim_buf_set_name(view, uri)
  end
  local command = (range and (range[1] .. "," .. range[2]) or "")
    .. (renamed and "saveas" or "write")
    .. (opts.bang and "!" or "")
    .. (opts.cmdarg or "")
    .. (opts.append and " >>" or "")
    .. (path and (" " .. vim.fn.fnameescape(path)) or "")
  local ok, err = pcall(vim.api.nvim_buf_call, source, function()
    if not vim.api.nvim_buf_is_loaded(source) or (range and vim.api.nvim_buf_get_changedtick(source) ~= tick) then
      error("Source changed during the write handoff")
    end
    vim.cmd(command)
  end)
  if vim.api.nvim_buf_is_valid(view) and vim.api.nvim_buf_is_valid(source) then
    M.rename(view, source)
    reader.refresh_source(source)
  end
  return ok, not ok and err or nil
end

function M.attach(view, source)
  if source then
    M.rename(view, source)
  end
  vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd", "FileAppendCmd" }, {
    buffer = view,
    nested = true,
    callback = function(args)
      local first = vim.api.nvim_buf_get_mark(view, "[")[1]
      local last = vim.api.nvim_buf_get_mark(view, "]")[1]
      local partial = args.event == "FileWriteCmd"
        or (args.event == "FileAppendCmd" and (first ~= 1 or last ~= vim.api.nvim_buf_line_count(view)))
      local ok, err = M.write(view, {
        file = args.file,
        bang = vim.v.cmdbang == 1,
        cmdarg = vim.v.cmdarg,
        append = args.event == "FileAppendCmd",
        partial = partial,
        first = first,
        last = last,
      })
      if not ok then
        error("MarkdownTableWrap: could not save Source Markdown: " .. tostring(err))
      end
    end,
  })
end

local function restore(view)
  local reader = require("markdown-table-wrap.reader")
  if
    not vim.api.nvim_buf_is_valid(view)
    or reader.is_reader(view)
    or vim.b[view].markdown_table_wrap_restoring
    or vim.b[view].markdown_table_wrap_auxiliary
  then
    return
  end
  local name = vim.api.nvim_buf_get_name(view)
  if name:sub(1, #prefix) ~= prefix then
    return
  end
  vim.b[view].markdown_table_wrap_restoring = true
  local modified = vim.bo[view].modified
  vim.b[view].markdown_table_wrap_auxiliary = true
  vim.bo[view].buftype = "acwrite"
  vim.bo[view].buflisted = false
  vim.bo[view].swapfile = false
  vim.bo[view].modifiable = false
  vim.bo[view].modified = modified
  M.attach(view)
  if modified then
    vim.notify(
      "MarkdownTableWrap: modified restored Reader kept for recovery; reopen the Source separately",
      vim.log.levels.WARN
    )
    return
  end
  local encoded = name:match("^markdown%-table%-wrap://reader/v1/%d+/(.+)$")
  local path = encoded and encoded:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  if not path or path:find("[%z\1-\31\127]") or not (path:match("^/") or path:match("^%a:[/\\]")) then
    vim.notify(
      "MarkdownTableWrap: this saved Reader has no recoverable Source path; reopen the Markdown file",
      vim.log.levels.WARN
    )
    return
  end

  -- Session scripts restore window options/cursors after BufReadCmd. Defer
  -- replacement until they finish; the placeholder cannot own file writes.
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(view) or vim.api.nvim_buf_get_name(view) ~= name or vim.bo[view].modified then
      return
    end
    local ok, err = pcall(function()
      local source = vim.fn.bufadd(path)
      vim.fn.bufload(source)
      if not vim.api.nvim_buf_is_loaded(source) then
        error("the backing Source could not be loaded")
      end
      vim.bo[source].buflisted = true
      for _, winid in ipairs(vim.fn.win_findbuf(view)) do
        vim.api.nvim_win_call(winid, function()
          vim.cmd("keepjumps buffer " .. source)
        end)
      end
      if vim.api.nvim_buf_is_valid(view) then
        vim.api.nvim_buf_delete(view, { force = true })
      end
    end)
    if not ok then
      vim.notify("MarkdownTableWrap: could not restore Reader Source: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

function M.install(group)
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = prefix .. "*",
    nested = true,
    callback = function(args)
      local reader = require("markdown-table-wrap.reader")
      if reader.source_changedtick(args.buf) then
        -- :edit in a live Reader unloads and re-reads it; rebuild the
        -- projection instead of leaving an empty buffer. :edit also lists
        -- the buffer, but a Reader must never become a duplicate document.
        reader.refresh(args.buf)
        vim.bo[args.buf].buflisted = false
        return
      end
      restore(args.buf)
    end,
  })
  local function scan()
    for _, view in ipairs(vim.api.nvim_list_bufs()) do
      -- :file/:saveas may leave the old URI as an unloaded alternate buffer.
      -- Only a loaded placeholder needs recovery; opening an unloaded URI
      -- later goes through BufReadCmd. Never resurrect old alternate paths.
      if vim.api.nvim_buf_is_loaded(view) then
        restore(view)
      end
    end
  end
  vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = scan })
  vim.schedule(scan)
end

return M
