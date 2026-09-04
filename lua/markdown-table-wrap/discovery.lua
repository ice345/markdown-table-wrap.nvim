local M = {}
local container = require("markdown-table-wrap.container")
local fence = require("markdown-table-wrap.fence")
local pipes = require("markdown-table-wrap.pipes")

local configured_backend = "auto"
local statuses = {}

local function delimiter_candidate(line)
  local count = 0
  if not pipes.has(line or "") then
    return false
  end
  for _, segment in ipairs(pipes.segments(line or "")) do
    local cell = line:sub(segment.start_col, segment.end_col)
    local value = vim.trim(cell):gsub("%s+", ""):gsub("^:", ""):gsub(":$", "")
    if #value < 3 or value:match("^%-+$") == nil then
      return false
    end
    count = count + 1
  end
  return count > 0
end

local function lua_ranges(lines)
  local ranges = {}
  local fenced_lines = fence.mask(lines)
  local lnum = 1
  while lnum <= #lines do
    local line = lines[lnum]
    local current = container.line(line)
    local following = lines[lnum + 1] and container.line(lines[lnum + 1]) or nil
    if fenced_lines[lnum] then
      lnum = lnum + 1
    elseif
      following
      and container.same(current, following)
      and pipes.has(current.content)
      and delimiter_candidate(following.content)
    then
      local finish = lnum + 1
      while finish + 1 <= #lines do
        local candidate = container.line(lines[finish + 1])
        if fenced_lines[finish + 1] or not container.same(current, candidate) or vim.trim(candidate.content) == "" then
          break
        end
        finish = finish + 1
      end
      table.insert(ranges, { start_lnum = lnum, end_lnum = finish, backend = "lua" })
      lnum = finish + 1
    else
      lnum = lnum + 1
    end
  end
  return ranges
end

local function treesitter_ranges(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "Tree-sitter discovery requires a live buffer"
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, vim.bo[bufnr].filetype)
  if not ok or not parser then
    return nil, "no compatible Markdown Tree-sitter parser"
  end
  local parsed_ok, trees = pcall(parser.parse, parser)
  if not parsed_ok or not trees or not trees[1] then
    return nil, "Markdown Tree-sitter parser failed"
  end
  local ranges = {}
  local function visit(node)
    local node_type = node:type()
    if node_type == "pipe_table" or node_type == "table" then
      local start_row, _, end_row, end_col = node:range()
      table.insert(ranges, {
        start_lnum = start_row + 1,
        end_lnum = end_row + (end_col > 0 and 1 or 0),
        backend = "treesitter",
      })
      return
    end
    for child in node:iter_children() do
      visit(child)
    end
  end
  local visit_ok = pcall(visit, trees[1]:root())
  if not visit_ok then
    return nil, "Markdown Tree-sitter tree could not be traversed"
  end
  if #ranges == 0 then
    return nil, "Markdown parser exposes no pipe-table nodes"
  end
  table.sort(ranges, function(a, b)
    return a.start_lnum < b.start_lnum
  end)
  return ranges
end

function M.configure(opts)
  opts = type(opts) == "table" and opts or {}
  configured_backend = vim.tbl_contains({ "auto", "lua", "treesitter" }, opts.backend) and opts.backend or "auto"
end

function M.discover(bufnr, lines, opts)
  opts = type(opts) == "table" and opts or {}
  local requested = opts.backend or configured_backend
  local used = "lua"
  local reason
  local ranges

  if requested == "treesitter" then
    ranges, reason = treesitter_ranges(bufnr)
    if ranges then
      used = "treesitter"
    else
      ranges = lua_ranges(lines)
      used = "lua"
    end
  else
    -- Auto intentionally keeps the deterministic Lua scanner until a measured
    -- corpus demonstrates that Tree-sitter is a net benefit.
    ranges = lua_ranges(lines)
    if requested == "auto" then
      reason = "auto currently prefers the guaranteed Lua backend"
    end
  end

  local status = {
    requested = requested,
    used = used,
    fallback_reason = reason,
    range_count = #ranges,
  }
  if bufnr then
    statuses[bufnr] = status
  end
  return ranges, status
end

function M.status(bufnr)
  return statuses[bufnr]
    or { requested = configured_backend, used = "lua", fallback_reason = "not run", range_count = 0 }
end

function M.clear(bufnr)
  statuses[bufnr] = nil
end

return M
