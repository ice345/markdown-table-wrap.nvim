local M = {}

local plugs = {
  ["<Plug>(MarkdownTableWrapToggleReader)"] = "toggle_reader",
  ["<Plug>(MarkdownTableWrapToggleInline)"] = "toggle_inline",
  ["<Plug>(MarkdownTableWrapEditSource)"] = "edit_source",
  ["<Plug>(MarkdownTableWrapClose)"] = "close",
  ["<Plug>(MarkdownTableWrapRefresh)"] = "refresh",
  ["<Plug>(MarkdownTableWrapOpen)"] = "open",
  ["<Plug>(MarkdownTableWrapOpenSplit)"] = "open_split",
  ["<Plug>(MarkdownTableWrapOpenVSplit)"] = "open_vsplit",
  ["<Plug>(MarkdownTableWrapOpenTab)"] = "open_tab",
  ["<Plug>(MarkdownTableWrapNextBuffer)"] = "next_buffer",
  ["<Plug>(MarkdownTableWrapPreviousBuffer)"] = "previous_buffer",
  ["<Plug>(MarkdownTableWrapAlternateBuffer)"] = "alternate_buffer",
  ["<Plug>(MarkdownTableWrapSplitSource)"] = "split_source",
  ["<Plug>(MarkdownTableWrapVSplitSource)"] = "vsplit_source",
  ["<Plug>(MarkdownTableWrapTabSource)"] = "tab_source",
  ["<Plug>(MarkdownTableWrapInspect)"] = "inspect",
  ["<Plug>(MarkdownTableWrapHelp)"] = "help",
  ["<Plug>(MarkdownTableWrapCopyCell)"] = "copy_cell",
  ["<Plug>(MarkdownTableWrapPutCell)"] = "put_cell",
  ["<Plug>(MarkdownTableWrapCopyTable)"] = "copy_table",
  ["<Plug>(MarkdownTableWrapExportTSV)"] = "export_tsv",
  ["<Plug>(MarkdownTableWrapExportCSV)"] = "export_csv",
  ["<Plug>(MarkdownTableWrapViewportLeft)"] = "viewport_left",
  ["<Plug>(MarkdownTableWrapViewportRight)"] = "viewport_right",
  ["<Plug>(MarkdownTableWrapFormatTable)"] = "format_table",
  ["<Plug>(MarkdownTableWrapAddRow)"] = "add_row_table",
  ["<Plug>(MarkdownTableWrapDeleteRow)"] = "delete_row_table",
  ["<Plug>(MarkdownTableWrapMoveRowUp)"] = "move_row_up_table",
  ["<Plug>(MarkdownTableWrapMoveRowDown)"] = "move_row_down_table",
  ["<Plug>(MarkdownTableWrapAddColumn)"] = "add_column_table",
  ["<Plug>(MarkdownTableWrapDeleteColumn)"] = "delete_column_table",
  ["<Plug>(MarkdownTableWrapMoveColumnLeft)"] = "move_column_left_table",
  ["<Plug>(MarkdownTableWrapMoveColumnRight)"] = "move_column_right_table",
  ["<Plug>(MarkdownTableWrapToggleAlignment)"] = "toggle_alignment_table",
  ["<Plug>(MarkdownTableWrapEditCell)"] = "open_cell_popup_table",
}

local function register_plugs()
  for lhs, action in pairs(plugs) do
    local action_name = action
    vim.keymap.set("n", lhs, function()
      require("markdown-table-wrap.actions").run(action_name)
    end, { silent = true, desc = "Markdown table: " .. action_name })
  end
end

local function register_preview_commands(plugin)
  vim.api.nvim_create_user_command("MarkdownTablePreview", function()
    plugin.preview()
  end, { desc = "Preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableInlinePreview", function()
    plugin.inline_preview()
  end, { desc = "Inline preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableFloatPreview", function()
    plugin.float_preview()
  end, { desc = "Floating preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableReader", function()
    plugin.reader_preview()
  end, { desc = "Open the current Markdown buffer in the rendered reader", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleReader", function()
    plugin.toggle_reader()
  end, { desc = "Toggle the rendered Markdown reader", force = true })

  vim.api.nvim_create_user_command("MarkdownTableEditSource", function()
    plugin.edit_source()
  end, { desc = "Leave the rendered reader and edit the Markdown source", force = true })

  vim.api.nvim_create_user_command("MarkdownTableTogglePreview", function()
    plugin.toggle_preview()
  end, { desc = "Toggle wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleInline", function()
    plugin.toggle_inline()
  end, { desc = "Toggle inline Markdown table rendering", force = true })

  vim.api.nvim_create_user_command("MarkdownTableClosePreview", function()
    plugin.close_preview()
  end, { desc = "Close wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableRefresh", function()
    plugin.action("refresh")
  end, { desc = "Force refresh Markdown table rendering", force = true })
end

local function register_state_commands(plugin)
  vim.api.nvim_create_user_command("MarkdownTableEnableAutoPreview", function()
    plugin.enable_auto_preview()
  end, { desc = "Enable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableDisableAutoPreview", function()
    plugin.disable_auto_preview()
  end, { desc = "Disable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleAutoPreview", function()
    plugin.toggle_auto_preview()
  end, { desc = "Toggle automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableStatus", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local reader = require("markdown-table-wrap.reader")
    local reader_active = reader.is_reader(bufnr)
    local active = require("markdown-table-wrap.inline").is_active(bufnr)
    local source_bufnr = reader_active and reader.source_bufnr(bufnr) or bufnr
    local paused = plugin.state.paused_buffers[source_bufnr] == true
    local config = plugin.get_buffer_config(source_bufnr)
    vim.notify(
      string.format(
        "MarkdownTableWrap: auto=%s paused=%s active=%s reader=%s mode=%s/%s wrap=%s",
        tostring(config.auto_preview),
        tostring(paused),
        tostring(active),
        tostring(reader_active),
        config.preview_mode,
        config.inline_mode .. (config.inline_viewport_scrolling and "/viewport" or "/full"),
        config.inline_wrap_scope
      ),
      vim.log.levels.INFO
    )
  end, { desc = "Show Markdown table wrap status", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleInlineViewport", function()
    plugin.toggle_inline_viewport_scrolling()
  end, { desc = "Toggle inline viewport scrolling for long rendered tables", force = true })
end

local function register_navigation_commands(plugin)
  vim.api.nvim_create_user_command("MarkdownTableNextCell", function()
    require("markdown-table-wrap.nav").move_horizontal(1)
  end, { desc = "Move to the next Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTablePrevCell", function()
    require("markdown-table-wrap.nav").move_horizontal(-1)
  end, { desc = "Move to the previous Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTableNextRow", function()
    require("markdown-table-wrap.nav").move_vertical(1)
  end, { desc = "Move to the same Markdown table cell in the next row", force = true })

  vim.api.nvim_create_user_command("MarkdownTablePrevRow", function()
    require("markdown-table-wrap.nav").move_vertical(-1)
  end, { desc = "Move to the same Markdown table cell in the previous row", force = true })

  local target_commands = {
    MarkdownTableOpen = { action = "open", desc = "Open the Markdown target under the cursor" },
    MarkdownTableOpenSplit = { action = "open_split", desc = "Open the Markdown target in a split" },
    MarkdownTableOpenVSplit = { action = "open_vsplit", desc = "Open the Markdown target in a vertical split" },
    MarkdownTableOpenTab = { action = "open_tab", desc = "Open the Markdown target in a tab" },
    MarkdownTableOpenLink = {
      action = "open",
      desc = "Open the Markdown target under the cursor (compatibility alias)",
    },
  }
  for command, spec in pairs(target_commands) do
    local action_name = spec.action
    local description = spec.desc
    vim.api.nvim_create_user_command(command, function()
      plugin.action(action_name)
    end, { desc = description, force = true })
  end

  vim.api.nvim_create_user_command("MarkdownTableInspect", function()
    plugin.action("inspect")
  end, { desc = "Inspect the active Markdown table view and Source context", force = true })

  vim.api.nvim_create_user_command("MarkdownTableHelp", function()
    plugin.action("help")
  end, { desc = "Show Markdown table view actions and configured keys", force = true })
end

local function register_scroll_commands(plugin)
  vim.api.nvim_create_user_command("MarkdownTableScrollDown", function(opts)
    local count = tonumber(opts.count) or 1
    plugin.scroll_view(count > 0 and count or 1)
  end, { desc = "Scroll rendered Markdown table view down", count = true, force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollUp", function(opts)
    local count = tonumber(opts.count) or 1
    plugin.scroll_view(-(count > 0 and count or 1))
  end, { desc = "Scroll rendered Markdown table view up", count = true, force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollTop", function()
    plugin.scroll_view_to("top")
  end, { desc = "Scroll rendered Markdown table view to the top", force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollBottom", function()
    plugin.scroll_view_to("bottom")
  end, { desc = "Scroll rendered Markdown table view to the bottom", force = true })

  vim.api.nvim_create_user_command("MarkdownTableViewportLeft", function(opts)
    plugin.shift_wide_table_viewport(-(tonumber(opts.count) or 1))
  end, { desc = "Show earlier columns in a wide table viewport", count = true, force = true })

  vim.api.nvim_create_user_command("MarkdownTableViewportRight", function(opts)
    plugin.shift_wide_table_viewport(tonumber(opts.count) or 1)
  end, { desc = "Show later columns in a wide table viewport", count = true, force = true })
end

local function register_data_commands(plugin)
  vim.api.nvim_create_user_command("MarkdownTableYankCell", function()
    plugin.copy_rendered_cell()
  end, { desc = "Copy the displayed Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTablePutCell", function()
    plugin.action("put_cell")
  end, { desc = "Replace the current Reader cell from the unnamed register", force = true })

  vim.api.nvim_create_user_command("MarkdownTableYankTable", function()
    plugin.copy_rendered_table()
  end, { desc = "Copy the rendered Markdown table", force = true })

  vim.api.nvim_create_user_command("MarkdownTableExport", function(opts)
    local format = vim.trim(opts.args or "")
    if format == "" then
      format = "tsv"
    end
    plugin.export_table({ format = format, all = opts.bang })
  end, {
    desc = "Export the current Markdown table as TSV or CSV",
    bang = true,
    nargs = "?",
    complete = function()
      return { "tsv", "csv" }
    end,
    force = true,
  })

  local edit_commands = {
    MarkdownTableFormat = "format",
    MarkdownTableAddRow = "add_row",
    MarkdownTableDeleteRow = "delete_row",
    MarkdownTableMoveRowUp = "move_row_up",
    MarkdownTableMoveRowDown = "move_row_down",
    MarkdownTableAddColumn = "add_column",
    MarkdownTableDeleteColumn = "delete_column",
    MarkdownTableMoveColumnLeft = "move_column_left",
    MarkdownTableMoveColumnRight = "move_column_right",
    MarkdownTableToggleAlignment = "toggle_alignment",
    MarkdownTableEditCell = "open_cell_popup",
  }
  for command, action in pairs(edit_commands) do
    local editor_action = action
    vim.api.nvim_create_user_command(command, function()
      plugin.edit_table(editor_action)
    end, { desc = "Edit the current Markdown table in Source", force = true })
  end
end

function M.register(plugin)
  register_plugs()
  register_preview_commands(plugin)
  register_state_commands(plugin)
  register_navigation_commands(plugin)
  register_scroll_commands(plugin)
  register_data_commands(plugin)
end

return M
