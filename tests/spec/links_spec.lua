local h = require("tests.helpers")

local function delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

h.test("link targets classify URLs files anchors wiki links and images", function()
  local links = require("markdown-table-wrap.links")
  local source = "/tmp/course/index.md"

  h.assert_eq("URL target", links.classify("https://example.com", { source_path = source }).kind, "external")
  h.assert_eq("same-document anchor", links.classify("#section", { source_path = source }).kind, "anchor")
  h.assert_eq("relative file", links.classify("week/one.md", { source_path = source }).path, "/tmp/course/week/one.md")
  h.assert_eq("file anchor", links.classify("week/one.md#topic", { source_path = source }).kind, "file_anchor")
  h.assert_eq("wiki link", links.classify("notes", { source_path = source, kind = "wiki_link" }).kind, "wiki")
  h.assert_eq(
    "wiki extension",
    links.classify("notes", { source_path = source, kind = "wiki_link" }).path,
    "/tmp/course/notes.md"
  )
  local wiki_anchor = links.classify("notes#topic", { source_path = source, kind = "wiki_link" })
  h.assert_eq("wiki anchor keeps wiki target kind", wiki_anchor.kind, "wiki")
  h.assert_eq("wiki anchor extension", wiki_anchor.path, "/tmp/course/notes.md")
  h.assert_eq("wiki anchor is retained", wiki_anchor.anchor, "topic")
  h.assert_eq("image target", links.classify("image.png", { source_path = source, kind = "image" }).kind, "image")
  h.assert_eq(
    "local file URI",
    links.classify("file:///tmp/space%20name.md", { source_path = source }).path,
    "/tmp/space name.md"
  )
  h.assert_eq(
    "remote file URI host is refused",
    links.classify("file://example.com/file.md", { source_path = source }).kind,
    "unresolved"
  )
  h.assert_eq("unnamed Source is unresolved", links.classify("relative.md", {}).kind, "unresolved")
  h.assert_eq(
    "bare URL is extracted",
    links.extract("visit https://example.com/docs.", source)[1].raw,
    "https://example.com/docs"
  )
end)

h.test("external link opening enforces the configured scheme allowlist", function()
  local links = require("markdown-table-wrap.links")
  local original_open = vim.ui.open
  local opened
  vim.ui.open = function(target)
    opened = target
  end
  local target = links.classify("obsidian://vault/note", {})
  local context = { config = { link = { allowed_schemes = { "http", "https" } } } }
  h.assert_false("unknown scheme is refused", links.open_target(target, context, { silent = true }))
  h.assert_eq("refused scheme is not delegated to the OS", opened, nil)
  context.config.link.allowed_schemes = { "obsidian" }
  h.assert_true("explicitly allowed custom scheme opens", links.open_target(target, context, { silent = true }))
  h.assert_eq("allowed custom scheme reaches vim.ui.open", opened, "obsidian://vault/note")
  vim.ui.open = original_open
end)

h.test("absolute files line targets and file anchors open at the requested location", function()
  local plugin = require("markdown-table-wrap")
  local target_path = vim.fn.tempname() .. ".md"
  vim.fn.writefile({ "# Start", "middle", "## Topic", "last" }, target_path)
  plugin.setup({ auto_preview = false })

  h.with_buffer({ "[line](" .. target_path .. ":2)" }, function(bufnr)
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_true("absolute line target opens", plugin.action("open"))
    h.assert_eq("line suffix positions cursor", vim.api.nvim_win_get_cursor(0)[1], 2)
    delete_buffer(vim.api.nvim_get_current_buf())
  end)

  h.with_buffer({ "[anchor](" .. target_path .. "#topic)" }, function(bufnr)
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_true("absolute file anchor opens", plugin.action("open"))
    h.assert_eq("file anchor positions cursor", vim.api.nvim_win_get_cursor(0)[1], 3)
    delete_buffer(vim.api.nvim_get_current_buf())
  end)
  vim.fn.delete(target_path)
end)

h.test("custom resolver receives target context and requested strategy", function()
  local plugin = require("markdown-table-wrap")
  local received = nil
  plugin.setup({
    auto_preview = false,
    link = {
      resolver = function(target, context, strategy)
        received = { target = target, context = context, strategy = strategy }
        return "noop"
      end,
    },
  })

  h.with_buffer({ "[site](https://example.com)" }, function(bufnr)
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_true("custom resolver handles target", plugin.action("open_vsplit"))
    h.assert_eq("resolver receives external target", received.target.kind, "external")
    h.assert_eq("resolver receives Source context", received.context.source_bufnr, bufnr)
    h.assert_eq("resolver receives strategy", received.strategy, "vsplit")
  end)
end)

h.test("Float links use rendered metadata and open files from the Source window", function()
  local plugin = require("markdown-table-wrap")
  local dir = vim.fn.tempname()
  local source_path = dir .. "/index.md"
  local target_path = dir .. "/target.md"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "# Target" }, target_path)
  plugin.setup({ auto_preview = false, preview_mode = "float" })

  h.with_buffer({
    "| Name | File |",
    "| --- | --- |",
    "| target | [open](target.md) |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].buftype = ""
    vim.api.nvim_buf_set_name(source_bufnr, source_path)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.bo[source_bufnr].modified = false
    vim.api.nvim_win_set_cursor(0, { 3, 12 })
    plugin.float_preview()
    local float_bufnr = plugin.state.buf
    local float_winid = plugin.state.win
    local cursor = nil
    for row, line_object in ipairs(plugin.state.float_rendered.line_objects) do
      for _, chunk in ipairs(line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url == "target.md" then
          cursor = { row, chunk.start_col }
        end
      end
    end
    vim.api.nvim_win_set_cursor(float_winid, cursor)
    h.assert_eq("Float context is recognized", plugin.get_state(float_bufnr).mode, "float")
    h.assert_true("Float file target opens", plugin.action("open"))
    h.assert_false("Float window is disposed", vim.api.nvim_win_is_valid(float_winid))
    h.assert_eq(
      "file opens in normal Source window",
      vim.fn.resolve(vim.api.nvim_buf_get_name(0)),
      vim.fn.resolve(target_path)
    )
    delete_buffer(vim.api.nvim_get_current_buf())
  end)

  vim.fn.delete(target_path)
  vim.fn.delete(dir, "d")
end)

h.test("relative Markdown files open inside Neovim from Source", function()
  local plugin = require("markdown-table-wrap")
  local dir = vim.fn.tempname()
  local source_path = dir .. "/index.md"
  local target_path = dir .. "/target.md"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "# Source" }, source_path)
  vim.fn.writefile({ "# Target", "content" }, target_path)

  plugin.setup({ auto_preview = false })
  h.with_buffer({ "[open target](target.md)" }, function(source_bufnr)
    vim.bo[source_bufnr].buftype = ""
    vim.api.nvim_buf_set_name(source_bufnr, source_path)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.bo[source_bufnr].modified = false
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    h.assert_true("Source-relative open succeeds", require("markdown-table-wrap.actions").run("open"))
    h.assert_eq(
      "target opens in current Neovim window",
      vim.fn.resolve(vim.api.nvim_buf_get_name(0)),
      vim.fn.resolve(target_path)
    )
    delete_buffer(vim.api.nvim_get_current_buf())
  end)

  vim.fn.delete(target_path)
  vim.fn.delete(source_path)
  vim.fn.delete(dir, "d")
end)

h.test("Reader file and anchor navigation remains Source-relative", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local dir = vim.fn.tempname()
  local source_path = dir .. "/index.md"
  local target_path = dir .. "/target.md"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "# Source" }, source_path)
  vim.fn.writefile({ "# Target" }, target_path)

  plugin.setup({ auto_preview = false, preview_mode = "reader" })
  h.with_buffer({
    "# Section",
    "",
    "[jump](#section)",
    "",
    "| Name | File |",
    "| --- | --- |",
    "| Target | [open](target.md) |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].buftype = ""
    vim.api.nvim_buf_set_name(source_bufnr, source_path)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.bo[source_bufnr].modified = false

    local reader_bufnr = plugin.reader_preview()
    local state = reader.get_state(reader_bufnr)
    local file_cursor = nil
    for row, line_object in ipairs(state.line_objects) do
      for _, chunk in ipairs(type(line_object) == "table" and line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url == "target.md" then
          file_cursor = { row, chunk.start_col }
          break
        end
      end
      if file_cursor then
        break
      end
    end

    vim.api.nvim_win_set_cursor(0, file_cursor)
    h.assert_true("Reader relative file opens", require("markdown-table-wrap.actions").run("open"))
    h.assert_false("file navigation closes disposable Reader", reader.is_reader(reader_bufnr))
    h.assert_eq(
      "Reader file target uses Source directory",
      vim.fn.resolve(vim.api.nvim_buf_get_name(0)),
      vim.fn.resolve(target_path)
    )
    delete_buffer(vim.api.nvim_get_current_buf())

    vim.api.nvim_set_current_buf(source_bufnr)
    local second_reader = plugin.reader_preview()
    local second_state = reader.get_state(second_reader)
    vim.api.nvim_win_set_cursor(0, { second_state.source_to_reader[3], 3 })
    h.assert_true("Reader same-document anchor opens", require("markdown-table-wrap.actions").run("open"))
    h.assert_eq("anchor returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_eq("anchor lands on heading", vim.api.nvim_win_get_cursor(0)[1], 1)
  end)

  vim.fn.delete(target_path)
  vim.fn.delete(source_path)
  vim.fn.delete(dir, "d")
end)

h.test("missing Reader file targets do not destroy the current view", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local path = vim.fn.tempname() .. ".md"
  plugin.setup({ auto_preview = false, preview_mode = "reader" })

  h.with_buffer({ "[missing](not-there.md)" }, function(source_bufnr)
    vim.bo[source_bufnr].buftype = ""
    vim.api.nvim_buf_set_name(source_bufnr, path)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.bo[source_bufnr].modified = false
    local reader_bufnr = plugin.reader_preview()
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    h.assert_false(
      "missing target reports failure",
      require("markdown-table-wrap.actions").run("open", { silent = true })
    )
    h.assert_true("missing target keeps Reader active", reader.is_reader(reader_bufnr))
    h.assert_eq("missing target keeps current view", vim.api.nvim_get_current_buf(), reader_bufnr)
    plugin.close_reader()
  end)
end)

h.test("missing Reader file anchors do not destroy the current view", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local dir = vim.fn.tempname()
  local source_path = dir .. "/index.md"
  local target_path = dir .. "/target.md"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "# Existing" }, target_path)
  plugin.setup({ auto_preview = false, preview_mode = "reader" })

  h.with_buffer({ "[missing anchor](target.md#absent)" }, function(source_bufnr)
    vim.bo[source_bufnr].buftype = ""
    vim.api.nvim_buf_set_name(source_bufnr, source_path)
    vim.bo[source_bufnr].filetype = "markdown"
    vim.bo[source_bufnr].modified = false
    local reader_bufnr = plugin.reader_preview()
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    h.assert_false("missing file anchor reports failure", plugin.action("open", { silent = true }))
    h.assert_true("missing file anchor keeps Reader", reader.is_reader(reader_bufnr))
    h.assert_eq("missing file anchor keeps view", vim.api.nvim_get_current_buf(), reader_bufnr)
    plugin.close_reader()
  end)

  vim.fn.delete(target_path)
  vim.fn.delete(dir, "d")
end)

h.test("multiple Markdown targets use the deterministic selector", function()
  local plugin = require("markdown-table-wrap")
  local original_select = vim.ui.select
  local original_open = vim.ui.open
  local opened = nil
  vim.ui.select = function(items, _, callback)
    callback(items[2])
  end
  vim.ui.open = function(target)
    opened = target
  end

  plugin.setup({ auto_preview = false })
  h.with_buffer({ "[one](https://one.test) text [two](https://two.test)" }, function(bufnr)
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 25 })
    h.assert_true("selector is opened", require("markdown-table-wrap.actions").run("open"))
    h.assert_eq("selector choice is opened", opened, "https://two.test")
  end)

  vim.ui.select = original_select
  vim.ui.open = original_open
end)
