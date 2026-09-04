local M = {}

local buffers = {}
local enabled = true
local counters = { hits = 0, misses = 0, writes = 0 }

local function entry(bufnr)
  buffers[bufnr] = buffers[bufnr] or { stages = {} }
  return buffers[bufnr]
end

function M.configure(opts)
  opts = type(opts) == "table" and opts or {}
  enabled = opts.enabled ~= false
  if not enabled then
    M.clear()
  end
end

function M.get(bufnr, stage, key, changedtick)
  if not enabled or not bufnr then
    counters.misses = counters.misses + 1
    return nil
  end
  local buffer = buffers[bufnr]
  local value = buffer and buffer.stages[stage]
  if value and value.key == key and value.changedtick == changedtick then
    counters.hits = counters.hits + 1
    return vim.deepcopy(value.value)
  end
  counters.misses = counters.misses + 1
  return nil
end

-- Internal derived-model fast path. Callers must treat the returned value as
-- read-only; public boundaries continue to use get() and receive an isolated
-- copy.
function M.get_ref(bufnr, stage, key, changedtick)
  if not enabled or not bufnr then
    counters.misses = counters.misses + 1
    return nil
  end
  local buffer = buffers[bufnr]
  local value = buffer and buffer.stages[stage]
  if value and value.key == key and value.changedtick == changedtick then
    counters.hits = counters.hits + 1
    return value.value
  end
  counters.misses = counters.misses + 1
  return nil
end

function M.set(bufnr, stage, key, changedtick, value)
  if not enabled or not bufnr then
    return value
  end
  entry(bufnr).stages[stage] = {
    key = key,
    changedtick = changedtick,
    value = vim.deepcopy(value),
  }
  counters.writes = counters.writes + 1
  return value
end

-- Internal companion to get_ref(). Ownership transfers to the cache and the
-- value must not be mutated afterwards.
function M.set_ref(bufnr, stage, key, changedtick, value)
  if not enabled or not bufnr then
    return value
  end
  entry(bufnr).stages[stage] = {
    key = key,
    changedtick = changedtick,
    value = value,
  }
  counters.writes = counters.writes + 1
  return value
end

function M.clear_buffer(bufnr)
  buffers[bufnr] = nil
end

function M.clear()
  buffers = {}
  counters = { hits = 0, misses = 0, writes = 0 }
  local loaded, markdown = pcall(require, "markdown-table-wrap.markdown")
  if loaded and markdown.clear_cache then
    markdown.clear_cache()
  end
end

function M.inspect(bufnr)
  local stages = {}
  for name in pairs((buffers[bufnr] or {}).stages or {}) do
    table.insert(stages, name)
  end
  table.sort(stages)
  return {
    enabled = enabled,
    stages = stages,
    entries = #stages,
    hits = counters.hits,
    misses = counters.misses,
    writes = counters.writes,
    token_entries = package.loaded["markdown-table-wrap.markdown"]
        and require("markdown-table-wrap.markdown").cache_size()
      or 0,
  }
end

return M
