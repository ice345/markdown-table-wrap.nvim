local M = {}

M.version = "0.1.0"

local defaults = {
  max_width_ratio = 0.9,
  min_col_width = 8,
  max_col_width = 50,
  border = "rounded",
  use_unicode_border = true,
  table_border = "rounded",
  row_separator = true,
  preview_mode = "inline",
  inline_mode = "replace",
  inline_position = "above",
  dim_source = true,
  auto_preview = true,
  render_all = true,
  auto_preview_in_insert = false,
  clear_on_cursor_leave = true,
  clear_on_insert = true,
  debounce_ms = 80,
  overlay_priority = 10000,
  overlay_fill = true,
  inline_viewport_scrolling = true,
  highlight_preset = "tokyonight",
  fill_background = true,
  table_background = nil,
  theme_dir = nil,
  themes = {},
  highlights = {},
  map_gx = true,
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
}

M.config = vim.deepcopy(defaults)
M.state = {
  win = nil,
  buf = nil,
  inline_buf = nil,
  augroup = nil,
  refresh_token = 0,
  paused_buffers = {},
  last_signature = {},
}

local function is_markdown_buffer()
  local ft = vim.bo.filetype
  return ft == "markdown" or ft == "md" or ft == "quarto" or ft == "rmarkdown"
end

local function validate_config()
  M.config.max_width_ratio = tonumber(M.config.max_width_ratio) or defaults.max_width_ratio
  M.config.min_col_width = math.max(1, tonumber(M.config.min_col_width) or defaults.min_col_width)
  M.config.max_col_width = math.max(M.config.min_col_width, tonumber(M.config.max_col_width) or defaults.max_col_width)
  M.config.debounce_ms = math.max(0, tonumber(M.config.debounce_ms) or defaults.debounce_ms)
  M.config.overlay_priority = math.max(1, tonumber(M.config.overlay_priority) or defaults.overlay_priority)
  M.config.render_all = M.config.render_all ~= false
  M.config.overlay_fill = M.config.overlay_fill ~= false
  M.config.inline_viewport_scrolling = M.config.inline_viewport_scrolling ~= false
  M.config.map_gx = M.config.map_gx ~= false

  if M.config.preview_mode ~= "inline" and M.config.preview_mode ~= "float" then
    M.config.preview_mode = defaults.preview_mode
  end

  if M.config.inline_mode ~= "replace" and M.config.inline_mode ~= "insert" then
    M.config.inline_mode = defaults.inline_mode
  end

  if M.config.inline_position ~= "above" and M.config.inline_position ~= "below" then
    M.config.inline_position = defaults.inline_position
  end

  if M.config.table_border ~= "rounded" and M.config.table_border ~= "single" then
    M.config.table_border = defaults.table_border
  end

  local valid_presets = {}
  for _, preset in ipairs(require("markdown-table-wrap.theme").presets()) do
    valid_presets[preset] = true
  end
  if not valid_presets[M.config.highlight_preset] then
    M.config.highlight_preset = defaults.highlight_preset
  end
end

local function close_existing()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end

  if M.state.buf and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end

  M.state.win = nil
  M.state.buf = nil
end

local function table_signature(bufnr, table_info)
  local lines = vim.api.nvim_buf_get_lines(bufnr, table_info.start_lnum - 1, table_info.end_lnum, false)
  return table.concat({
    tostring(table_info.start_lnum),
    tostring(table_info.end_lnum),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(M.config.max_width_ratio),
    tostring(M.config.min_col_width),
    tostring(M.config.max_col_width),
    M.config.use_unicode_border and "unicode" or "ascii",
    tostring(M.config.table_border),
    tostring(M.config.row_separator),
    tostring(M.config.inline_mode),
    tostring(M.config.inline_viewport_scrolling),
    table.concat(lines, "\n"),
  }, "\31")
end

local function all_tables_signature(bufnr, tables)
  local parts = {
    tostring(vim.api.nvim_buf_get_changedtick(bufnr)),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(M.config.max_width_ratio),
    tostring(M.config.min_col_width),
    tostring(M.config.max_col_width),
    M.config.use_unicode_border and "unicode" or "ascii",
    tostring(M.config.table_border),
    tostring(M.config.row_separator),
    tostring(M.config.inline_mode),
    tostring(M.config.overlay_fill),
    tostring(M.config.inline_viewport_scrolling),
  }

  for _, table_info in ipairs(tables) do
    table.insert(parts, tostring(table_info.start_lnum))
    table.insert(parts, tostring(table_info.end_lnum))
  end

  return table.concat(parts, "\31")
end

function M.close_preview()
  close_existing()
  local bufnr = M.state.inline_buf or vim.api.nvim_get_current_buf()
  require("markdown-table-wrap.inline").clear(bufnr)
  M.state.inline_buf = nil
  M.state.paused_buffers[bufnr] = true
end

local function table_under_cursor(opts)
  opts = opts or {}

  if not is_markdown_buffer() then
    if not opts.silent then
      vim.notify("MarkdownTableWrap: preview is only available in Markdown buffers.", vim.log.levels.INFO)
    end
    return nil
  end

  local parser = require("markdown-table-wrap.parser")
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info, err = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if not opts.silent then
      vim.notify(err or "MarkdownTableWrap: cursor is not inside a Markdown pipe table.", vim.log.levels.INFO)
    end
    return nil
  end

  return bufnr, table_info
end

function M.inline_preview()
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return
  end

  close_existing()
  M.state.paused_buffers[bufnr] = nil
  require("markdown-table-wrap.inline").show(bufnr, table_info, M.config)
  M.state.last_signature[bufnr] = table_signature(bufnr, table_info)
  M.state.inline_buf = bufnr
end

function M.float_preview()
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return
  end

  close_existing()

  local render = require("markdown-table-wrap.render")
  local rendered = render.render_table(table_info, M.config)
  local buf, win = render.open_float(rendered, M.config)
  M.state.buf = buf
  M.state.win = win
end

function M.preview()
  if M.config.preview_mode == "float" then
    M.float_preview()
    return
  end

  M.inline_preview()
end

function M.refresh_auto(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local inline = require("markdown-table-wrap.inline")

  if not M.config.auto_preview and not opts.force then
    return
  end

  if M.state.paused_buffers[bufnr] and not opts.force then
    return
  end

  if not is_markdown_buffer() then
    inline.clear(bufnr)
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  if not M.config.auto_preview_in_insert and mode:match("^i") then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    return
  end

  local parser = require("markdown-table-wrap.parser")
  if M.config.render_all then
    local tables = parser.parse_all(bufnr)
    if #tables == 0 then
      inline.clear(bufnr)
      M.state.inline_buf = nil
      M.state.last_signature[bufnr] = nil
      return
    end

    local signature = all_tables_signature(bufnr, tables)
    if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
      inline.attach_window(bufnr)
      return
    end

    close_existing()
    inline.show_many(bufnr, tables, M.config)
    M.state.last_signature[bufnr] = signature
    M.state.inline_buf = bufnr
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if M.config.clear_on_cursor_leave ~= false then
      inline.clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end
    return
  end

  local signature = table_signature(bufnr, table_info)
  if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
    inline.attach_window(bufnr)
    return
  end

  close_existing()
  inline.show(bufnr, table_info, M.config)
  M.state.last_signature[bufnr] = signature
  M.state.inline_buf = bufnr
end

function M.schedule_refresh(opts)
  opts = opts or {}
  M.state.refresh_token = M.state.refresh_token + 1
  local token = M.state.refresh_token
  local delay = opts.immediate and 0 or M.config.debounce_ms

  vim.defer_fn(function()
    if token ~= M.state.refresh_token then
      return
    end

    if vim.api.nvim_get_current_buf() == 0 then
      return
    end

    M.refresh_auto(opts)
  end, delay)
end

function M.toggle_preview()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    close_existing()
    return
  end

  local inline = require("markdown-table-wrap.inline")
  local bufnr = vim.api.nvim_get_current_buf()
  if inline.is_active(bufnr) then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    M.state.paused_buffers[bufnr] = true
    return
  end

  M.preview()
end

function M.enable_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  M.state.paused_buffers[bufnr] = nil
  M.config.auto_preview = true
  M.refresh_auto({ force = true })
end

function M.disable_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  M.state.paused_buffers[bufnr] = true
  require("markdown-table-wrap.inline").clear(bufnr)
  if M.state.inline_buf == bufnr then
    M.state.inline_buf = nil
  end
  M.state.last_signature[bufnr] = nil
end

function M.toggle_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  if M.state.paused_buffers[bufnr] then
    M.enable_auto_preview()
  else
    M.disable_auto_preview()
  end
end

function M.toggle_inline_viewport_scrolling()
  M.config.inline_viewport_scrolling = not M.config.inline_viewport_scrolling
  local bufnr = vim.api.nvim_get_current_buf()
  require("markdown-table-wrap.inline").reset_view(bufnr)
  M.state.last_signature[bufnr] = nil
  M.refresh_auto({ force = true })
  vim.notify(
    string.format(
      "MarkdownTableWrap: inline viewport scrolling %s",
      M.config.inline_viewport_scrolling and "enabled" or "disabled"
    ),
    vim.log.levels.INFO
  )
end

function M.scroll_view(delta)
  if require("markdown-table-wrap.inline").scroll(vim.api.nvim_get_current_buf(), delta) then
    return
  end

  local keys = delta > 0 and [[\<C-E>]] or [[\<C-Y>]]
  vim.cmd("normal! " .. tostring(math.max(1, math.abs(delta))) .. keys)
end

function M.scroll_view_to(position)
  if require("markdown-table-wrap.inline").scroll_to(vim.api.nvim_get_current_buf(), position) then
    return
  end

  if position == "bottom" then
    vim.cmd("normal! G")
  else
    vim.cmd("normal! gg")
  end
end

local function create_autocmds()
  if M.state.augroup then
    vim.api.nvim_del_augroup_by_id(M.state.augroup)
  end

  M.state.augroup = vim.api.nvim_create_augroup("MarkdownTableWrap", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M.state.augroup,
    callback = function(args)
      if not is_markdown_buffer() then
        return
      end

      if M.config.render_all then
        return
      end

      M.schedule_refresh({ silent = true })
    end,
  })

  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "InsertLeave", "BufWinEnter", "WinScrolled", "VimResized" },
    {
      group = M.state.augroup,
      callback = function()
        if not is_markdown_buffer() then
          return
        end
        M.schedule_refresh({ silent = true })
      end,
    }
  )

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = M.state.augroup,
    callback = function()
      if M.config.auto_preview_in_insert or not M.config.clear_on_insert then
        return
      end

      local bufnr = vim.api.nvim_get_current_buf()
      require("markdown-table-wrap.inline").clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end,
  })

  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = M.state.augroup,
    callback = function(args)
      require("markdown-table-wrap.inline").attach_window(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = M.state.augroup,
    callback = function(args)
      if M.config.render_all then
        return
      end

      if M.config.clear_on_cursor_leave ~= false then
        require("markdown-table-wrap.inline").clear(args.buf)
        if M.state.inline_buf == args.buf then
          M.state.inline_buf = nil
        end
        M.state.last_signature[args.buf] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = M.state.augroup,
    callback = function(args)
      M.state.paused_buffers[args.buf] = nil
      M.state.last_signature[args.buf] = nil
      if M.state.inline_buf == args.buf then
        M.state.inline_buf = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = M.state.augroup,
    pattern = { "markdown", "md", "quarto", "rmarkdown" },
    callback = function(args)
      if not M.config.map_gx then
        return
      end

      vim.keymap.set("n", "gx", function()
        if not require("markdown-table-wrap.nav").open_link() then
          vim.cmd("normal! gx")
        end
      end, { buffer = args.buf, silent = true, desc = "Open Markdown table link" })
    end,
  })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate_config()
  create_autocmds()

  vim.api.nvim_create_user_command("MarkdownTablePreview", function()
    M.preview()
  end, { desc = "Preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableInlinePreview", function()
    M.inline_preview()
  end, { desc = "Inline preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableFloatPreview", function()
    M.float_preview()
  end, { desc = "Floating preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableTogglePreview", function()
    M.toggle_preview()
  end, { desc = "Toggle wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableClosePreview", function()
    M.close_preview()
  end, { desc = "Close wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableRefresh", function()
    M.refresh_auto({ force = true })
  end, { desc = "Force refresh Markdown table rendering", force = true })

  vim.api.nvim_create_user_command("MarkdownTableEnableAutoPreview", function()
    M.enable_auto_preview()
  end, { desc = "Enable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableDisableAutoPreview", function()
    M.disable_auto_preview()
  end, { desc = "Disable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleAutoPreview", function()
    M.toggle_auto_preview()
  end, { desc = "Toggle automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableStatus", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local active = require("markdown-table-wrap.inline").is_active(bufnr)
    local paused = M.state.paused_buffers[bufnr] == true
    vim.notify(
      string.format(
        "MarkdownTableWrap: auto=%s paused=%s active=%s mode=%s/%s",
        tostring(M.config.auto_preview),
        tostring(paused),
        tostring(active),
        M.config.preview_mode,
        M.config.inline_mode .. (M.config.inline_viewport_scrolling and "/viewport" or "/full")
      ),
      vim.log.levels.INFO
    )
  end, { desc = "Show Markdown table wrap status", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleInlineViewport", function()
    M.toggle_inline_viewport_scrolling()
  end, { desc = "Toggle inline viewport scrolling for long rendered tables", force = true })

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

  vim.api.nvim_create_user_command("MarkdownTableOpenLink", function()
    require("markdown-table-wrap.nav").open_link()
  end, { desc = "Open the first link in the current Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollDown", function(opts_cmd)
    local count = tonumber(opts_cmd.count) or 1
    M.scroll_view(count > 0 and count or 1)
  end, { desc = "Scroll rendered Markdown table view down", count = true, force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollUp", function(opts_cmd)
    local count = tonumber(opts_cmd.count) or 1
    M.scroll_view(-(count > 0 and count or 1))
  end, { desc = "Scroll rendered Markdown table view up", count = true, force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollTop", function()
    M.scroll_view_to("top")
  end, { desc = "Scroll rendered Markdown table view to the top", force = true })

  vim.api.nvim_create_user_command("MarkdownTableScrollBottom", function()
    M.scroll_view_to("bottom")
  end, { desc = "Scroll rendered Markdown table view to the bottom", force = true })

  if M.config.auto_preview and is_markdown_buffer() then
    M.schedule_refresh({ silent = true, immediate = true })
  end
end

return M
