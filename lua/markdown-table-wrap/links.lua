local M = {}

local function notify(message, level, opts)
  if not (opts or {}).silent then
    vim.notify("MarkdownTableWrap: " .. message, level or vim.log.levels.INFO)
  end
end

local function normalize_path(path)
  if vim.fs and vim.fs.normalize then
    return vim.fs.normalize(path)
  end
  return vim.fn.simplify(path)
end

local function source_directory(source_path)
  if not source_path or source_path == "" then
    return nil
  end
  if vim.fs and vim.fs.dirname then
    return vim.fs.dirname(source_path)
  end
  return vim.fn.fnamemodify(source_path, ":h")
end

local function split_anchor(raw)
  local hash = raw:find("#", 1, true)
  if not hash then
    return raw, nil
  end
  return raw:sub(1, hash - 1), raw:sub(hash + 1)
end

local function decode_anchor(anchor)
  return (anchor or ""):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function slugify(text)
  text = text:lower():gsub("%s+#+%s*$", ""):gsub("%s+", "-")
  text = text:gsub("[^%w%-%_\128-\255]", "")
  return text:gsub("%-+", "-")
end

function M.classify(raw, opts)
  opts = opts or {}
  raw = vim.trim(tostring(raw or ""))
  if raw:match("^<.*>$") then
    raw = raw:sub(2, -2)
  end
  if raw == "" then
    return { kind = "unresolved", raw = raw, reason = "empty target" }
  end

  local kind = opts.kind
  if kind == "wiki_link" then
    raw = raw:match("^([^|]+)") or raw
    raw = vim.trim(raw)
    local wiki_path, wiki_anchor = split_anchor(raw)
    if wiki_path ~= "" and not wiki_path:match("%.[%w]+$") then
      wiki_path = wiki_path .. ".md"
    end
    raw = wiki_path .. (wiki_anchor and ("#" .. wiki_anchor) or "")
  end

  local scheme = raw:match("^([%a][%w+%.%-]*):")
  if scheme and not raw:match("^%a:[/\\]") then
    return {
      kind = "external",
      raw = raw,
      scheme = scheme:lower(),
      label = opts.label,
      source_path = opts.source_path,
    }
  end

  if vim.startswith(raw, "#") then
    return {
      kind = "anchor",
      raw = raw,
      anchor = decode_anchor(raw:sub(2)),
      label = opts.label,
      source_path = opts.source_path,
    }
  end

  local path_part, anchor = split_anchor(raw)
  if vim.startswith(path_part, "~/") then
    path_part = vim.fn.expand(path_part)
  end
  local line = nil
  local line_path, line_number = path_part:match("^(.-):(%d+)$")
  if line_path and line_path ~= "" and not path_part:match("^%a:[/\\]") then
    path_part = line_path
    line = tonumber(line_number)
  end

  local base = source_directory(opts.source_path)
  local absolute
  if vim.fn.fnamemodify(path_part, ":p") == path_part or path_part:match("^%a:[/\\]") then
    absolute = normalize_path(path_part)
  elseif base then
    absolute = normalize_path(base .. "/" .. path_part)
  end

  if not absolute then
    return {
      kind = "unresolved",
      raw = raw,
      reason = "the Source buffer has no file path",
      label = opts.label,
    }
  end

  local target_kind = kind == "wiki_link" and "wiki"
    or (kind == "image" and "image" or (anchor and "file_anchor" or "file"))
  return {
    kind = target_kind,
    raw = raw,
    path = absolute,
    anchor = anchor and decode_anchor(anchor) or nil,
    line = line,
    label = opts.label,
    source_path = opts.source_path,
    exists = (vim.uv or vim.loop).fs_stat(absolute) ~= nil,
  }
end

local function overlaps(existing, start_col, end_col)
  for _, item in ipairs(existing) do
    if start_col < item.end_col and end_col > item.start_col then
      return true
    end
  end
  return false
end

function M.extract(line, source_path)
  line = tostring(line or "")
  local markdown = require("markdown-table-wrap.markdown")
  local candidates = {}

  for _, link in ipairs(markdown.extract_links(line)) do
    local target = M.classify(link.url, {
      kind = link.kind,
      label = link.text,
      source_path = source_path,
    })
    target.start_col = link.start_col
    target.end_col = link.end_col
    table.insert(candidates, target)
  end

  local cursor = 1
  while cursor <= #line do
    local start_col, end_col, value = line:find("%[%[([^%]]+)%]%]", cursor)
    if not start_col then
      break
    end
    if not overlaps(candidates, start_col - 1, end_col) then
      local target = M.classify(value, { kind = "wiki_link", label = value, source_path = source_path })
      target.start_col = start_col - 1
      target.end_col = end_col
      table.insert(candidates, target)
    end
    cursor = end_col + 1
  end

  cursor = 1
  while cursor <= #line do
    local start_col, end_col, value = line:find("<([%a][%w+%.%-]*:[^>]+)>", cursor)
    if not start_col then
      break
    end
    if not overlaps(candidates, start_col - 1, end_col) then
      local target = M.classify(value, { label = value, source_path = source_path })
      target.start_col = start_col - 1
      target.end_col = end_col
      table.insert(candidates, target)
    end
    cursor = end_col + 1
  end

  cursor = 1
  while cursor <= #line do
    local start_col, end_col, value = line:find("([%a][%w+%.%-]*://[^%s<>]+)", cursor)
    if not start_col then
      break
    end
    local trimmed = value:gsub("[%,%;%!%?%.%]%)]*$", "")
    end_col = end_col - (#value - #trimmed)
    if trimmed ~= "" and not overlaps(candidates, start_col - 1, end_col) then
      local target = M.classify(trimmed, { label = trimmed, source_path = source_path })
      target.start_col = start_col - 1
      target.end_col = end_col
      table.insert(candidates, target)
    end
    cursor = math.max(end_col + 1, start_col + 1)
  end

  table.sort(candidates, function(a, b)
    return a.start_col < b.start_col
  end)
  return candidates
end

local function rendered_targets(context)
  if context.mode ~= "reader" and context.mode ~= "float" then
    return {}
  end
  local row = context.cursor.view_lnum
  local line_object
  if context.mode == "reader" then
    line_object = require("markdown-table-wrap.reader").line_object(context.view_bufnr, row)
  else
    local rendered = require("markdown-table-wrap").state.float_rendered
    line_object = rendered and (rendered.line_objects or {})[row] or nil
  end
  local targets = {}
  for _, chunk in ipairs(type(line_object) == "table" and line_object.chunks or {}) do
    if
      (chunk.kind == "link" or chunk.kind == "image" or chunk.kind == "wiki_link")
      and chunk.url
      and chunk.url ~= ""
    then
      local target = M.classify(chunk.url, {
        kind = chunk.kind,
        source_path = context.source_path,
      })
      target.start_col = chunk.start_col
      target.end_col = chunk.end_col
      table.insert(targets, target)
    end
  end
  return targets
end

function M.targets(context)
  local targets = rendered_targets(context)
  if #targets > 0 then
    return targets, context.cursor.view_col or 0
  end

  if context.cell and context.cell.tokens then
    for _, link in
      ipairs(require("markdown-table-wrap.markdown").extract_links(context.cell, { coordinates = "source" }))
    do
      local target = M.classify(link.target, {
        kind = link.kind,
        label = link.text,
        source_path = context.source_path,
      })
      target.start_col = link.start_col
      target.end_col = link.end_col
      table.insert(targets, target)
    end
    if #targets > 0 then
      return targets, context.cursor.source_col or 0
    end
  end

  local lnum = context.cursor.source_lnum or 1
  local line = vim.api.nvim_buf_get_lines(context.source_bufnr, lnum - 1, lnum, false)[1] or ""
  return M.extract(line, context.source_path), context.cursor.source_col or 0
end

local function target_at_cursor(targets, col)
  for _, target in ipairs(targets) do
    if col >= (target.start_col or 0) and col < (target.end_col or 0) then
      return target
    end
  end
  return #targets == 1 and targets[1] or nil
end

local function find_anchor_in_lines(lines, anchor)
  anchor = slugify(decode_anchor(anchor))
  if anchor == "" then
    return 1
  end
  for lnum, line in ipairs(lines) do
    local explicit = line:match("{#([^}]+)}%s*$")
    local heading = line:match("^%s*#+%s+(.+)$")
    if (explicit and explicit == anchor) or (heading and slugify(heading) == anchor) then
      return lnum
    end
  end
  return nil
end

local function find_anchor(bufnr, anchor)
  return find_anchor_in_lines(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), anchor)
end

local function find_file_anchor(path, anchor)
  local bufnr = vim.fn.bufnr(path)
  if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    return find_anchor(bufnr, anchor)
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and find_anchor_in_lines(lines, anchor) or nil
end

local function leave_view(context)
  if context.mode == "float" then
    local plugin = require("markdown-table-wrap")
    local source_winid = plugin.state.float_source_winid
    plugin.close_preview()
    if source_winid and vim.api.nvim_win_is_valid(source_winid) then
      vim.api.nvim_set_current_win(source_winid)
    end
    return vim.api.nvim_get_current_buf() == context.source_bufnr
  end
  if context.mode ~= "reader" then
    return true
  end
  local source_bufnr = require("markdown-table-wrap.reader").close(context.view_bufnr)
  if source_bufnr then
    require("markdown-table-wrap").pause_buffer(source_bufnr)
    return true
  end
  return false
end

local function open_external(target, opts)
  if not vim.ui or type(vim.ui.open) ~= "function" then
    notify("vim.ui.open is unavailable for " .. target.raw, vim.log.levels.ERROR, opts)
    return false
  end
  local ok, err = pcall(vim.ui.open, target.raw)
  if not ok then
    notify("could not open " .. target.raw .. ": " .. tostring(err), vim.log.levels.ERROR, opts)
  end
  return ok
end

local function open_file(target, context, opts)
  if not target.exists then
    notify("file target does not exist: " .. tostring(target.path), vim.log.levels.ERROR, opts)
    return false
  end
  local anchor_lnum = nil
  if target.anchor then
    anchor_lnum = find_file_anchor(target.path, target.anchor)
    if not anchor_lnum then
      notify("anchor was not found in " .. target.path .. "#" .. target.anchor, vim.log.levels.ERROR, opts)
      return false
    end
  end
  if not leave_view(context) then
    return false
  end

  local commands = {
    edit = "edit",
    split = "split",
    vsplit = "vsplit",
    tab = "tabedit",
  }
  local command = commands[opts.strategy or "edit"] or "edit"
  local ok, err = pcall(vim.cmd, command .. " " .. vim.fn.fnameescape(target.path))
  if not ok then
    notify("could not open file target " .. target.path .. ": " .. tostring(err), vim.log.levels.ERROR, opts)
    return false
  end

  if target.line then
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(target.line, last)), 0 })
  elseif anchor_lnum then
    vim.api.nvim_win_set_cursor(0, { anchor_lnum, 0 })
  end
  return true
end

function M.open_target(target, context, opts)
  opts = opts or {}
  local resolver = (((context or {}).config or {}).link or {}).resolver
  if type(resolver) == "function" then
    local ok, result = pcall(resolver, vim.deepcopy(target), vim.deepcopy(context), opts.strategy or "edit")
    if not ok then
      notify("custom link resolver failed: " .. tostring(result), vim.log.levels.ERROR, opts)
      return false
    elseif result == false or result == "noop" then
      return true
    elseif result == true then
      return true
    elseif type(result) == "string" then
      if not vim.tbl_contains({ "edit", "split", "vsplit", "tab" }, result) then
        notify("custom link resolver returned an invalid strategy: " .. result, vim.log.levels.ERROR, opts)
        return false
      end
      opts.strategy = result
    end
  end

  if target.kind == "external" then
    return open_external(target, opts)
  elseif target.kind == "anchor" then
    local lnum = find_anchor(context.source_bufnr, target.anchor)
    if not lnum then
      notify("anchor was not found: #" .. tostring(target.anchor), vim.log.levels.ERROR, opts)
      return false
    end
    if not leave_view(context) then
      return false
    end
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    return true
  elseif target.path then
    return open_file(target, context, opts)
  end

  notify("unresolved target " .. vim.inspect(target.raw) .. ": " .. tostring(target.reason), vim.log.levels.ERROR, opts)
  return false
end

function M.open_at_context(context, opts)
  opts = opts or {}
  local targets, col = M.targets(context)
  local selected = target_at_cursor(targets, col)
  if selected then
    return M.open_target(selected, context, opts)
  end
  if #targets == 0 then
    notify("no Markdown link target is available at the current position", vim.log.levels.INFO, opts)
    return false
  end

  vim.ui.select(targets, {
    prompt = "Select Markdown target",
    format_item = function(target)
      return string.format("%s  %s", target.label or target.raw, target.path or target.raw)
    end,
  }, function(choice)
    if choice then
      M.open_target(choice, context, opts)
    end
  end)
  return true
end

return M
