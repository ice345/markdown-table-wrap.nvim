local h = require("tests.helpers")
local interaction_table = require("tests.fixtures.cell_interaction")

local function source_lines()
  return {
    "A paragraph outside the table.",
    "",
    "| Name | Link | Notes |",
    "| --- | --- | --- |",
    "| one | [GitHub documentation portal](https://github.com) | a deliberately long note that wraps across several Reader lines |",
  }
end

local function comparison_lines()
  return {
    "A paragraph outside the table.",
    "",
    "| 工具名称 | 主要功能 | 支持平台 | 优点 | 缺点 / 注意事项 | 适用场景 |",
    "| :--- | :--- | :--- | :--- | :--- | :--- |",
    "| **CrossOver** | 在 Mac/Linux 上运行 Windows 应用，基于 [Wine](https://www.winehq.org/)，无需安装 Windows 系统 | macOS、Linux | 资源占用低，与系统深度融合（如可以直接打开 `.exe` 文件），M 系列 Mac 性能较好 | 并非所有 Windows 软件都能完美运行，尤其是依赖反作弊系统的网游；需要一定的配置调整（如开启 D3DMetal） | Mac 用户偶尔运行 Windows 软件或老游戏 |",
    "| **Proton** | Steam 内置的兼容层，基于 Wine，专为 Linux 平台运行 Windows 游戏而开发 | Linux（Steam Deck 原生支持） | 与 Steam 深度集成，无需额外配置即可运行大部分 Windows 游戏；Valve 持续维护更新；对游戏手柄和全屏优化较好 | 仅限 Steam 平台游戏（非 Steam 游戏需要手动添加）；仅支持 Linux，Mac 用户无法使用；某些反作弊游戏仍然不兼容 | Linux 桌面玩家或 Steam Deck 用户 |",
    "| **Wine** | 开源的兼容层，将 Windows API 调用实时转换为 POSIX 调用，让 Linux/macOS 原生运行 Windows 程序 | macOS、Linux、BSD | 完全免费开源，社区活跃，高度可定制，没有任何商业限制；是 CrossOver 和 Proton 的底层技术核心 | 配置复杂，需要命令行操作和手动调整 DLL、注册表等；对新游戏或大型应用的支持滞后；几乎没有图形化界面 | 愿意投入时间折腾的高级用户 |",
    "| **Parallels Desktop** | Mac 上的高性能虚拟机，可以直接运行完整的 Windows 11 系统，支持融合模式（Coherence）无缝运行 Windows 应用 | macOS（Apple Silicon 和 Intel） | 兼容性最好，几乎可以运行所有 Windows 程序（包括依赖反作弊的游戏和企业级软件）；硬件虚拟化加速优秀；支持 DirectX 12 和 OpenGL | 资源消耗大（需要分配内存和 CPU 核心）；价格较高（订阅制或一次性买断较贵）；占用硬盘空间较大（需要完整的 Windows 镜像） | 需要频繁运行多种 Windows 软件或游戏，且对兼容性要求极高，愿意为稳定和易用付费的用户 |",
  }
end

local function delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function open_reader(width, lines, opts)
  local plugin = require("markdown-table-wrap")
  plugin.setup(vim.tbl_deep_extend("force", {
    auto_preview = false,
    preview_mode = "reader",
    max_width_ratio = 1,
    min_col_width = 4,
    max_col_width = 18,
    row_separator = true,
  }, opts or {}))
  local source_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[source_bufnr].buftype = "nofile"
  vim.bo[source_bufnr].swapfile = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, lines or source_lines())
  vim.api.nvim_set_current_buf(source_bufnr)
  vim.api.nvim_win_set_width(0, width or 72)
  local reader_bufnr = plugin.reader_preview()
  return plugin, source_bufnr, reader_bufnr
end

local function position_on_cell(reader_bufnr, source_lnum, column_index)
  local reader = require("markdown-table-wrap.reader")
  local state = reader.get_state(reader_bufnr)
  for row, line_object in ipairs(state.line_objects or {}) do
    for _, cell in ipairs(type(line_object) == "table" and line_object.cells or {}) do
      if cell.source_span and cell.source_span.start_lnum == source_lnum and cell.column_index == column_index then
        vim.api.nvim_win_set_cursor(0, { row, cell.start_col })
        return reader.cell_at_cursor(reader_bufnr)
      end
    end
  end
  return nil
end

local function close_and_delete(plugin, source_bufnr)
  if vim.api.nvim_get_current_buf() ~= source_bufnr then
    plugin.close_reader()
  end
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end

h.test("yic copies the original Markdown source of a wrapped cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  local cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("link cell is found in Reader", cell ~= nil)
  h.assert_true("link cell has multiple rendered segments", cell.render_end_row > cell.render_start_row)

  local cell_ops = require("markdown-table-wrap.cell_ops")
  h.assert_true("yic succeeds", cell_ops.yank(reader_bufnr))
  h.assert_eq("yic uses raw source", vim.fn.getreg('"'), "[GitHub documentation portal](https://github.com)")
  h.assert_eq(
    "yic populates the yank register",
    vim.fn.getreg("0"),
    "[GitHub documentation portal](https://github.com)"
  )
  vim.api.nvim_win_set_cursor(0, { cell.render_end_row, cell.render_start_col })
  h.assert_true("yic works from a wrapped continuation line", cell_ops.yank(reader_bufnr))
  h.assert_eq("wrapped-line yic remains raw", vim.fn.getreg('"'), "[GitHub documentation portal](https://github.com)")

  close_and_delete(plugin, source_bufnr)
end)

h.test("typed Reader cell operations use exact blockquote Source spans", function()
  local quoted = {
    "> | A | B |",
    "  > | --- | --- |",
    " > | one | [site](https://example.com) |",
  }
  local plugin, source_bufnr, reader_bufnr = open_reader(52, quoted)
  h.assert_true("quoted Reader cell is found", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.feedkeys("yic", "xt")
  vim.wait(80)
  h.assert_eq("quoted yic excludes quote and neighboring cells", vim.fn.getreg('"'), "[site](https://example.com)")
  h.assert_eq("quoted yic remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)

  h.assert_true("quoted Reader cell is found for delete", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.feedkeys("dic", "xt")
  vim.wait(80)
  h.assert_eq(
    "quoted dic clears only the Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1],
    " > | one |  |"
  )
  h.assert_eq("quoted dic remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("typed yic and vic handle CJK/link cells without border leakage", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(48, comparison_lines())
  local link_cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("comparison link cell is found", link_cell ~= nil)
  local yank_cursor = vim.api.nvim_win_get_cursor(0)
  vim.fn.setreg('"', "")
  vim.fn.feedkeys("yic", "xt")
  vim.wait(80)
  h.assert_eq(
    "typed yic copies exact link source",
    vim.fn.getreg('"'),
    "在 Mac/Linux 上运行 Windows 应用，基于 [Wine](https://www.winehq.org/)，无需安装 Windows 系统"
  )
  h.assert_eq("typed yic returns directly to Normal", vim.api.nvim_get_mode().mode, "n")
  h.assert_eq("typed yic stays in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  h.assert_deep_eq("typed yic does not leave a selection cursor", vim.api.nvim_win_get_cursor(0), yank_cursor)
  h.assert_true(
    "typed yic does not create a logical Visual marker",
    vim.b[reader_bufnr].markdown_table_wrap_cell_visual == nil
  )
  h.assert_eq(
    "typed yic leaves no Reader selection overlay",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, require("markdown-table-wrap.reader").visual_namespace(), 0, -1, {}),
    0
  )

  local visual_cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("comparison link cell is found for vic", visual_cell ~= nil)
  vim.fn.feedkeys("vic", "xt")
  vim.wait(80)
  h.assert_eq("typed vic enters blockwise Visual", vim.api.nvim_get_mode().mode, "\22")
  vim.fn.setreg("a", "named sentinel")
  vim.fn.feedkeys('"ay', "xt")
  vim.wait(80)
  local yanked = vim.fn.getreg('"')
  h.assert_eq(
    "vic yank uses the same raw Source cell as yic",
    yanked,
    "在 Mac/Linux 上运行 Windows 应用，基于 [Wine](https://www.winehq.org/)，无需安装 Windows 系统"
  )
  h.assert_false("vic yank excludes vertical borders", yanked:find("│", 1, true) ~= nil)
  h.assert_eq("vic yank honors the selected register", vim.fn.getreg("a"), yanked)
  h.assert_eq("vic yank returns to Normal mode", vim.api.nvim_get_mode().mode, "n")
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell operations refresh a stale Reader projection before resolving", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("initial cell is found", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.api.nvim_buf_set_lines(source_bufnr, 4, 5, false, {
    "| one | [updated source](https://example.com) | a deliberately long note that wraps across several Reader lines |",
  })
  h.assert_true("stale Reader yic succeeds", require("markdown-table-wrap.cell_ops").yank(reader_bufnr))
  h.assert_eq("stale Reader resolves new Source span", vim.fn.getreg('"'), "[updated source](https://example.com)")
  close_and_delete(plugin, source_bufnr)
end)

h.test("typed dic uses the operator-pending cell object without changing neighbors", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("cell is found for typed delete", cell ~= nil)
  vim.fn.setreg("0", "previous yank")
  vim.fn.setreg("-", "previous small delete")
  vim.fn.feedkeys("dic", "xt")
  vim.wait(80)
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_true("typed dic clears only the selected source", line:find("| one |  |", 1, true) ~= nil)
  h.assert_true("typed dic keeps the neighboring cell", line:find("a deliberately long note", 1, true) ~= nil)
  h.assert_eq("typed dic yanks removed source", vim.fn.getreg('"'), "[GitHub documentation portal](https://github.com)")
  h.assert_eq(
    "typed dic uses the small-delete register",
    vim.fn.getreg("-"),
    "[GitHub documentation portal](https://github.com)"
  )
  h.assert_eq("typed dic preserves yank register zero", vim.fn.getreg("0"), "previous yank")
  h.assert_eq("typed dic returns to Normal", vim.api.nvim_get_mode().mode, "n")
  close_and_delete(plugin, source_bufnr)
end)

h.test("typed yic and dic honor an explicit named register", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local raw = "[GitHub documentation portal](https://github.com)"
  h.assert_true("cell is found for named yank", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("a", "named sentinel")
  vim.fn.setreg("0", "zero sentinel")
  vim.fn.feedkeys('"ayic', "xt")
  vim.wait(80)
  h.assert_eq("named yic writes register a", vim.fn.getreg("a"), raw)
  h.assert_eq("named yic makes unnamed point at register a", vim.fn.getreg('"'), raw)
  h.assert_eq("named yic preserves register zero", vim.fn.getreg("0"), "zero sentinel")

  h.assert_true("cell is found for named delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("a", "named sentinel")
  vim.fn.setreg("-", "small-delete sentinel")
  vim.fn.feedkeys('"adic', "xt")
  vim.wait(80)
  h.assert_eq("named dic writes register a", vim.fn.getreg("a"), raw)
  h.assert_eq("named dic makes unnamed point at register a", vim.fn.getreg('"'), raw)
  h.assert_eq("named dic preserves the small-delete register", vim.fn.getreg("-"), "small-delete sentinel")

  close_and_delete(plugin, source_bufnr)
end)

h.test("black-hole dic preserves all observable registers", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for black-hole delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("0", "zero sentinel")
  vim.fn.setreg("-", "small-delete sentinel")
  vim.fn.setreg("a", "named sentinel")
  local before = {
    unnamed = vim.fn.getreg('"'),
    zero = vim.fn.getreg("0"),
    small = vim.fn.getreg("-"),
    named = vim.fn.getreg("a"),
  }

  vim.fn.feedkeys('"_dic', "xt")
  vim.wait(80)

  h.assert_eq(
    "black-hole dic clears only the Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_eq("black-hole dic preserves unnamed", vim.fn.getreg('"'), before.unnamed)
  h.assert_eq("black-hole dic preserves register zero", vim.fn.getreg("0"), before.zero)
  h.assert_eq("black-hole dic preserves small-delete", vim.fn.getreg("-"), before.small)
  h.assert_eq("black-hole dic preserves named registers", vim.fn.getreg("a"), before.named)

  close_and_delete(plugin, source_bufnr)
end)

h.test("cell text objects reject counts without changing Source", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local original = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  h.assert_true("cell is found for counted yank", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "counted yank sentinel")
  local original_notify = vim.notify
  vim.notify = function() end
  vim.fn.feedkeys("2yic", "xt")
  vim.wait(80)
  vim.notify = original_notify
  h.assert_eq("2yic preserves the unnamed register", vim.fn.getreg('"'), "counted yank sentinel")
  h.assert_deep_eq("2yic leaves Source unchanged", vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), original)

  h.assert_true("cell is found for counted delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  original_notify = vim.notify
  vim.notify = function() end
  vim.fn.feedkeys("2dic", "xt")
  vim.wait(80)
  vim.notify = original_notify
  h.assert_deep_eq("2dic leaves Source unchanged", vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), original)
  h.assert_eq("2dic returns to Normal", vim.api.nvim_get_mode().mode, "n")

  h.assert_true("cell is found for counted change", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  original_notify = vim.notify
  vim.notify = function() end
  vim.fn.feedkeys("2cic", "xt")
  vim.wait(80)
  vim.notify = original_notify
  h.assert_deep_eq("2cic leaves Source unchanged", vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), original)
  h.assert_eq("2cic stays in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)

  h.assert_true("cell is found for counted visual", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  original_notify = vim.notify
  vim.notify = function() end
  vim.fn.feedkeys("2vic", "xt")
  vim.wait(80)
  vim.notify = original_notify
  h.assert_eq("2vic returns to Normal", vim.api.nvim_get_mode().mode, "n")
  h.assert_deep_eq("2vic leaves Source unchanged", vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), original)

  h.assert_true("cell is found for a Visual-mode count", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  original_notify = vim.notify
  vim.notify = function() end
  vim.fn.feedkeys("v2ic", "xt")
  vim.wait(80)
  vim.notify = original_notify
  h.assert_eq("v2ic returns to Normal", vim.api.nvim_get_mode().mode, "n")
  h.assert_deep_eq("v2ic leaves Source unchanged", vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), original)

  close_and_delete(plugin, source_bufnr)
end)

h.test("vic selects every rendered segment of one logical cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  local cell = position_on_cell(reader_bufnr, 5, 3)
  h.assert_true("wrapped note cell is found", cell ~= nil)

  h.assert_true("vic succeeds", require("markdown-table-wrap.cell_ops").visual(reader_bufnr))
  h.assert_eq("vic uses blockwise Visual mode", vim.api.nvim_get_mode().mode, "\22")
  local marks = vim.api.nvim_buf_get_extmarks(
    reader_bufnr,
    require("markdown-table-wrap.reader").visual_namespace(),
    0,
    -1,
    { details = true }
  )
  h.assert_eq("vic covers each wrapped cell line", #marks, cell.render_end_row - cell.render_start_row + 1)
  for _, mark in ipairs(marks) do
    local line = vim.api.nvim_buf_get_lines(reader_bufnr, mark[2], mark[2] + 1, false)[1] or ""
    local highlighted = mark[4].virt_text[1][1]
    h.assert_true("vic starts inside each exact cell segment", mark[3] < #line)
    h.assert_false("vic overlay excludes the following border", highlighted:find("│", 1, true) ~= nil)
    h.assert_eq("vic overlay uses Visual highlight", mark[4].virt_text[1][2], "Visual")
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  h.assert_eq(
    "vic visual overlay clears after leaving Visual",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, require("markdown-table-wrap.reader").visual_namespace(), 0, -1, {}),
    0
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("vic restores an existing Visual y mapping after yank", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  local cell = position_on_cell(reader_bufnr, 5, 3)
  h.assert_true("cell is found for Visual mapping restore", cell ~= nil)

  vim.keymap.set("x", "y", function() end, {
    buffer = reader_bufnr,
    desc = "user visual yank",
  })
  vim.keymap.set("x", "d", function() end, {
    buffer = reader_bufnr,
    desc = "user visual delete",
  })
  h.assert_true(
    "vic succeeds with a user Visual y mapping",
    require("markdown-table-wrap.cell_ops").visual(reader_bufnr)
  )
  vim.fn.feedkeys("y", "xt")
  vim.wait(80)
  local restored = vim.fn.maparg("y", "x", false, true)
  h.assert_eq("Visual y mapping is restored", restored.desc, "user visual yank")
  restored = vim.fn.maparg("d", "x", false, true)
  h.assert_eq("Visual d mapping is restored", restored.desc, "user visual delete")
  h.assert_eq("Visual yank returns to Normal", vim.api.nvim_get_mode().mode, "n")
  close_and_delete(plugin, source_bufnr)
end)

h.test("Reader reconfiguration restores logical Visual mappings", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(58)
  h.assert_true("cell is found before Reader reconfiguration", position_on_cell(reader_bufnr, 5, 3) ~= nil)
  vim.keymap.set("x", "y", function() end, {
    buffer = reader_bufnr,
    desc = "user visual yank before reconfigure",
  })
  h.assert_true("vic succeeds before reconfiguration", require("markdown-table-wrap.cell_ops").visual(reader_bufnr))

  h.assert_true(
    "Reader reconfiguration succeeds during vic",
    require("markdown-table-wrap.reader").reconfigure(reader_bufnr, plugin.get_buffer_config(source_bufnr))
  )

  local restored = vim.fn.maparg("y", "x", false, true)
  h.assert_eq(
    "reconfiguration restores the user's Visual mapping",
    restored.desc,
    "user visual yank before reconfigure"
  )
  h.assert_true(
    "reconfiguration clears the logical visual marker",
    vim.b[reader_bufnr].markdown_table_wrap_cell_visual == nil
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  close_and_delete(plugin, source_bufnr)
end)

h.test("vic routes delete, change, and put through the logical Source cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for vicd", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  local cell_ops = require("markdown-table-wrap.cell_ops")
  h.assert_true("vic selection succeeds for delete", cell_ops.visual(reader_bufnr))
  h.assert_true("vicd dispatch succeeds", cell_ops.visual_operator(reader_bufnr, "d"))
  vim.wait(80)
  h.assert_eq(
    "vicd clears only the Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_eq("vicd remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  close_and_delete(plugin, source_bufnr)

  plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for vicc", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  cell_ops = require("markdown-table-wrap.cell_ops")
  h.assert_true("vic selection succeeds for change", cell_ops.visual(reader_bufnr))
  h.assert_true("vicc dispatch succeeds", cell_ops.visual_operator(reader_bufnr, "c"))
  vim.fn.feedkeys("replaced\27", "xt")
  vim.wait(80)
  h.assert_eq(
    "vicc changes only the Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one | replaced | a deliberately long note that wraps across several Reader lines |"
  )
  close_and_delete(plugin, source_bufnr)

  plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for vic put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("a", "**named replacement**")
  h.assert_true("vic selection succeeds for put", require("markdown-table-wrap.cell_ops").visual(reader_bufnr))
  vim.fn.feedkeys('"ap', "xt")
  vim.wait(80)
  h.assert_eq(
    "vic put reads the selected named register",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one | **named replacement** | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_eq("vic put preserves its input register", vim.fn.getreg("a"), "**named replacement**")
  h.assert_eq(
    "vic put places replaced Source in unnamed",
    vim.fn.getreg('"'),
    "[GitHub documentation portal](https://github.com)"
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("native v and V get visible Reader selection overlays inside tables", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local cell = position_on_cell(reader_bufnr, 5, 2)
  h.assert_true("cell is found for native visual selection", cell ~= nil)

  vim.cmd("normal! v")
  require("markdown-table-wrap.reader").update_visual_selection(reader_bufnr)
  local namespace = require("markdown-table-wrap.reader").visual_namespace()
  h.assert_true(
    "native v installs a selection overlay",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, namespace, 0, -1, {}) > 0
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  position_on_cell(reader_bufnr, 5, 2)
  vim.cmd("normal! V")
  require("markdown-table-wrap.reader").update_visual_selection(reader_bufnr)
  h.assert_true(
    "native V installs a selection overlay",
    #vim.api.nvim_buf_get_extmarks(reader_bufnr, namespace, 0, -1, {}) > 0
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  close_and_delete(plugin, source_bufnr)
end)

h.test("dic clears only the selected cell and preserves table structure", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  h.assert_true("dic succeeds", require("markdown-table-wrap.cell_ops").delete(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_eq(
    "dic leaves the row and neighboring cells",
    line,
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_false("dic removes only cell content", line:find("GitHub", 1, true) ~= nil)
  h.assert_eq(
    "dic places deleted source in unnamed register",
    vim.fn.getreg('"'),
    "[GitHub documentation portal](https://github.com)"
  )
  h.assert_true("dic keeps Reader active", require("markdown-table-wrap.reader").is_reader(reader_bufnr))
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell put inserts register text into the exact Source cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "**new label**")
  h.assert_true("cell put succeeds", require("markdown-table-wrap.cell_ops").put(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_eq(
    "cell put preserves neighboring cells and pipes",
    line,
    "| one | **new label** | a deliberately long note that wraps across several Reader lines |"
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell put keeps a multiline register on the same table row", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for multiline put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "first\nsecond")
  h.assert_true("multiline cell put succeeds", require("markdown-table-wrap.cell_ops").put(reader_bufnr))
  local line = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  h.assert_true("multiline cell put flattens newlines", line:find("first second", 1, true) ~= nil)
  h.assert_eq("multiline cell put keeps the row pipe", line:sub(-1), "|")
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell put Plug mapping honors an explicit register", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for put Plug mapping", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("a", "**plug replacement**")

  local plug = vim.api.nvim_replace_termcodes("<Plug>(MarkdownTableWrapPutCell)", true, false, true)
  vim.fn.feedkeys('"a' .. plug, "xt")
  vim.wait(80)

  h.assert_eq(
    "put Plug mapping reads the selected register",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one | **plug replacement** | a deliberately long note that wraps across several Reader lines |"
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("cell mutations respect a read-only Source buffer", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for read-only guard", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.bo[source_bufnr].readonly = true
  h.assert_false("read-only delete is rejected", require("markdown-table-wrap.cell_ops").delete(reader_bufnr))
  h.assert_true(
    "read-only Source remains unchanged",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]:find("GitHub", 1, true) ~= nil
  )
  vim.bo[source_bufnr].readonly = false
  close_and_delete(plugin, source_bufnr)
end)

h.test("cic leaves Source unchanged when Reader cannot close", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for failed change", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  local original = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  vim.fn.setreg('"', "existing register")

  local group = vim.api.nvim_create_augroup("MarkdownTableWrapTestFailedCellChange", { clear = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = reader_bufnr,
    callback = function()
      error("forced Reader close failure")
    end,
  })

  local original_notify = vim.notify
  vim.notify = function() end
  local ok, changed = pcall(require("markdown-table-wrap.cell_ops").change, reader_bufnr)
  vim.notify = original_notify
  h.assert_true("failed cic is handled without propagating an error", ok)
  h.assert_false("cic reports the failed Reader transition", changed)
  h.assert_deep_eq(
    "failed cic preserves Source exactly",
    vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
    original
  )
  h.assert_eq("failed cic preserves the unnamed register", vim.fn.getreg('"'), "existing register")
  h.assert_eq("failed cic stays in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  h.assert_true("failed cic keeps Reader state valid", require("markdown-table-wrap.reader").is_reader(reader_bufnr))

  vim.api.nvim_del_augroup_by_id(group)
  close_and_delete(plugin, source_bufnr)
end)

h.test("cic refuses a stale cell span after Source changes while leaving Reader", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for stale transition", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg('"', "existing register")

  local group = vim.api.nvim_create_augroup("MarkdownTableWrapTestStaleCellChange", { clear = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = reader_bufnr,
    once = true,
    callback = function()
      vim.api.nvim_buf_set_lines(source_bufnr, 0, 1, false, { "Changed while leaving Reader." })
    end,
  })

  local original_notify = vim.notify
  vim.notify = function() end
  local ok, changed = pcall(require("markdown-table-wrap.cell_ops").change, reader_bufnr)
  vim.notify = original_notify
  h.assert_true("stale cic is handled without propagating an error", ok)
  h.assert_false("cic rejects a changed Source projection", changed)
  h.assert_true(
    "stale cic preserves the target cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]:find("[GitHub documentation portal]", 1, true) ~= nil
  )
  h.assert_eq("stale cic preserves the unnamed register", vim.fn.getreg('"'), "existing register")
  h.assert_eq("stale cic leaves Source visible", vim.api.nvim_get_current_buf(), source_bufnr)

  vim.api.nvim_del_augroup_by_id(group)
  close_and_delete(plugin, source_bufnr)
end)

h.test("cic clears the Source cell and enters Source Insert mode", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  h.assert_true("cell is found for change", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  h.assert_true("cic succeeds", require("markdown-table-wrap.cell_ops").change(reader_bufnr))
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt")
  h.assert_eq("cic returns to Source", vim.api.nvim_get_current_buf(), source_bufnr)
  h.assert_eq(
    "cic clears only cell content",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_false("cic keeps normal Reader re-entry unpaused", plugin.state.paused_buffers[source_bufnr] == true)
  -- Headless Neovim cannot enter an interactive Insert mode, but the action
  -- still requests Source Insert in a real UI via :startinsert.
  close_and_delete(plugin, source_bufnr)
end)

h.test("typed cic change and insertion form one undo block", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local original = vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1]
  vim.bo[source_bufnr].undolevels = -1
  vim.bo[source_bufnr].undolevels = 1000
  h.assert_true("cell is found for typed cic undo", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.feedkeys("cicreplacement\27", "xt")
  vim.wait(80)
  h.assert_eq(
    "typed cic writes replacement",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one | replacement | a deliberately long note that wraps across several Reader lines |"
  )
  vim.cmd("undo")
  h.assert_eq(
    "one undo restores the complete original cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    original
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("dot repeats the last cic replacement on the current logical cell", function()
  local lines = source_lines()
  table.insert(lines, "| two | second link | another note |")
  local plugin, source_bufnr, reader_bufnr = open_reader(72, lines)
  h.assert_true("first cell is found for repeat", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.feedkeys("cicreplacement\27", "xt")
  vim.wait(80)
  h.assert_eq(
    "initial cic replacement is committed",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one | replacement | a deliberately long note that wraps across several Reader lines |"
  )

  reader_bufnr = plugin.reader_preview()
  h.assert_true("second cell is found for dot repeat", position_on_cell(reader_bufnr, 6, 2) ~= nil)
  vim.fn.feedkeys(".", "xt")
  vim.wait(80)
  h.assert_eq(
    "dot applies the same replacement to the current logical cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 5, 6, false)[1],
    "| two | replacement | another note |"
  )
  h.assert_eq("cell dot repeat remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("dot repeats dic on the current logical cell", function()
  local lines = source_lines()
  table.insert(lines, "| two | second link | another note |")
  local plugin, source_bufnr, reader_bufnr = open_reader(72, lines)
  h.assert_true("first cell is found for repeated delete", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.feedkeys("dic", "xt")
  vim.wait(80)

  h.assert_true("second cell is found for repeated delete", position_on_cell(reader_bufnr, 6, 2) ~= nil)
  vim.fn.feedkeys(".", "xt")
  vim.wait(80)

  h.assert_eq(
    "initial dic clears the first Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )
  h.assert_eq(
    "dot clears the second Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 5, 6, false)[1],
    "| two |  | another note |"
  )
  close_and_delete(plugin, source_bufnr)
end)

h.test("dot repeats the committed cell-put value", function()
  local lines = source_lines()
  table.insert(lines, "| two | second link | another note |")
  local plugin, source_bufnr, reader_bufnr = open_reader(72, lines)
  h.assert_true("first cell is found for repeated put", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.setreg("a", "**put value**")
  h.assert_true(
    "initial named cell put succeeds",
    require("markdown-table-wrap.cell_ops").put(reader_bufnr, { register = "a" })
  )
  vim.fn.setreg("a", "later register value")

  h.assert_true("second cell is found for repeated put", position_on_cell(reader_bufnr, 6, 2) ~= nil)
  vim.fn.feedkeys(".", "xt")
  vim.wait(80)

  h.assert_eq(
    "dot repeats the original put value",
    vim.api.nvim_buf_get_lines(source_bufnr, 5, 6, false)[1],
    "| two | **put value** | another note |"
  )
  h.assert_eq("dot does not reread a changed input register", vim.fn.getreg("a"), "later register value")
  close_and_delete(plugin, source_bufnr)
end)

h.test("c delegates to the captured Source mapping from a Reader cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local calls = 0
  vim.keymap.set("n", "c", function()
    calls = calls + 1
  end, { buffer = source_bufnr })
  require("markdown-table-wrap.reader").reconfigure(reader_bufnr, plugin.get_buffer_config(source_bufnr))
  h.assert_true("cell is found for Source c mapping delegation", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  h.assert_true("c fallback succeeds", require("markdown-table-wrap.cell_ops").change_or_fallback(reader_bufnr))
  h.assert_eq("c fallback runs once", calls, 1)
  h.assert_eq("c fallback runs in Source", vim.api.nvim_get_current_buf(), source_bufnr)
  h.assert_false("c fallback closes Reader", require("markdown-table-wrap.reader").is_reader(reader_bufnr))
  close_and_delete(plugin, source_bufnr)
end)

h.test("native cip remains available in Reader prose", function()
  local plugin, source_bufnr = open_reader(72)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  vim.fn.feedkeys("cipreplacement\27", "xt")
  vim.wait(80)

  h.assert_eq(
    "native cip changes the Source paragraph",
    vim.api.nvim_buf_get_lines(source_bufnr, 0, 1, false)[1],
    "replacement"
  )
  h.assert_eq("native cip leaves Reader for Source editing", vim.api.nvim_get_current_buf(), source_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("Reader c remains a native Source operator prefix inside a long table cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  local original = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  h.assert_true("CrossOver type cell is found", position_on_cell(reader_bufnr, 3, 2) ~= nil)

  vim.fn.feedkeys("c\27", "xt")
  vim.wait(80)

  h.assert_deep_eq(
    "c followed by Esc does not eagerly clear the cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
    original
  )
  h.assert_eq("native c prefix transitions to Source", vim.api.nvim_get_current_buf(), source_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("mistyped yic and dic sequences cannot operate on rendered Reader rows", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  local original_source = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  local original_reader = vim.api.nvim_buf_get_lines(reader_bufnr, 0, -1, false)

  local invalid_sequences = {
    "yj",
    "yk",
    "yij",
    "yik",
    "yy",
    "yw",
    "y$",
    "yap",
    "yjP",
    '"ayj',
    "2yj",
    "dj",
    "dk",
    "dij",
    "dik",
    "dd",
    "dw",
    "d$",
    "dap",
    "dgg",
    "djP",
    '"adj',
    "2dj",
    "d2j",
  }
  for _, keys in ipairs(invalid_sequences) do
    h.assert_true(keys .. " target cell is found", position_on_cell(reader_bufnr, 3, 2) ~= nil)
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.fn.setreg("0", "yank-zero sentinel")
    vim.fn.setreg("-", "small-delete sentinel")
    vim.fn.setreg("a", "named sentinel")
    vim.fn.setreg('"', "unnamed sentinel")
    local registers = {
      unnamed = vim.fn.getreg('"'),
      zero = vim.fn.getreg("0"),
      small = vim.fn.getreg("-"),
      named = vim.fn.getreg("a"),
    }
    vim.cmd("let v:errmsg = ''")
    local original_notify = vim.notify
    vim.notify = function() end

    vim.fn.feedkeys(keys, "xt")
    vim.wait(80)

    vim.notify = original_notify
    h.assert_eq(keys .. " remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
    h.assert_eq(keys .. " returns to Normal mode", vim.api.nvim_get_mode().mode, "n")
    h.assert_deep_eq(keys .. " does not move the Reader cursor", vim.api.nvim_win_get_cursor(0), cursor)
    h.assert_deep_eq(
      keys .. " does not change Source",
      vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
      original_source
    )
    h.assert_deep_eq(
      keys .. " does not change rendered Reader rows",
      vim.api.nvim_buf_get_lines(reader_bufnr, 0, -1, false),
      original_reader
    )
    h.assert_eq(keys .. " preserves unnamed", vim.fn.getreg('"'), registers.unnamed)
    h.assert_eq(keys .. " preserves yank register zero", vim.fn.getreg("0"), registers.zero)
    h.assert_eq(keys .. " preserves small-delete", vim.fn.getreg("-"), registers.small)
    h.assert_eq(keys .. " preserves named registers", vim.fn.getreg("a"), registers.named)
    h.assert_false(keys .. " never raises E21", vim.v.errmsg:find("E21", 1, true) ~= nil)
  end

  close_and_delete(plugin, source_bufnr)
end)

h.test("guarded yic and dic remain usable from macros", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  local raw = "兼容层（基于Wine）[bilibili](https://www.bilibili.com)"
  h.assert_true("macro yank target cell is found", position_on_cell(reader_bufnr, 3, 2) ~= nil)

  vim.fn.setreg("q", "yic", "c")
  vim.fn.feedkeys("@q", "xt")
  vim.wait(80)
  h.assert_eq("macro yic copies the exact Source cell", vim.fn.getreg('"'), raw)
  h.assert_eq("macro yic remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)

  vim.fn.setreg("q", "dic", "c")
  vim.fn.feedkeys("@q", "xt")
  vim.wait(80)
  h.assert_true(
    "macro dic clears only the target cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1]:find("| **CrossOver** |  |", 1, true) ~= nil
  )
  h.assert_eq("macro dic remains in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)

  close_and_delete(plugin, source_bufnr)
end)

h.test("long table cell text objects preserve raw Source registers and reject counts", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  local reader = require("markdown-table-wrap.reader")
  local raw = "兼容层（基于Wine）[bilibili](https://www.bilibili.com)"
  h.assert_true("CrossOver type cell is found for register operations", position_on_cell(reader_bufnr, 3, 2) ~= nil)

  vim.fn.setreg("a", "named sentinel")
  vim.fn.setreg("0", "zero sentinel")
  vim.fn.feedkeys('"ayic', "xt")
  vim.wait(80)
  h.assert_eq('long-table "ayic writes exact raw Source', vim.fn.getreg("a"), raw)
  h.assert_eq('long-table "ayic updates unnamed', vim.fn.getreg('"'), raw)
  h.assert_eq('long-table "ayic preserves register zero', vim.fn.getreg("0"), "zero sentinel")

  h.assert_true("CrossOver type cell is found for vic yank", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.feedkeys("vic", "xt")
  vim.wait(80)
  vim.fn.feedkeys('"by', "xt")
  vim.wait(80)
  h.assert_eq("long-table vic yank matches yic raw Source", vim.fn.getreg("b"), raw)

  h.assert_true("CrossOver type cell is found for named delete", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.setreg("-", "small-delete sentinel")
  vim.fn.feedkeys('"adic', "xt")
  vim.wait(80)
  h.assert_eq('long-table "adic writes exact raw Source', vim.fn.getreg("a"), raw)
  h.assert_eq('long-table "adic preserves small-delete', vim.fn.getreg("-"), "small-delete sentinel")
  h.assert_true(
    'long-table "adic clears only the selected cell',
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1]:find("| **CrossOver** |  |", 1, true) ~= nil
  )

  vim.api.nvim_buf_call(source_bufnr, function()
    vim.cmd("undo")
  end)
  h.assert_true("Reader refreshes after undoing named delete", reader.refresh(reader_bufnr))
  h.assert_true("CrossOver type cell is found for black-hole delete", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.setreg('"', "unnamed sentinel")
  vim.fn.setreg("0", "zero sentinel")
  vim.fn.setreg("-", "small-delete sentinel")
  vim.fn.setreg("a", "named sentinel")
  local before_black_hole = {
    unnamed = vim.fn.getreg('"'),
    zero = vim.fn.getreg("0"),
    small = vim.fn.getreg("-"),
    named = vim.fn.getreg("a"),
  }
  vim.fn.feedkeys('"_dic', "xt")
  vim.wait(80)
  h.assert_eq('long-table "_dic preserves unnamed', vim.fn.getreg('"'), before_black_hole.unnamed)
  h.assert_eq('long-table "_dic preserves register zero', vim.fn.getreg("0"), before_black_hole.zero)
  h.assert_eq('long-table "_dic preserves small-delete', vim.fn.getreg("-"), before_black_hole.small)
  h.assert_eq('long-table "_dic preserves named register', vim.fn.getreg("a"), before_black_hole.named)

  vim.api.nvim_buf_call(source_bufnr, function()
    vim.cmd("undo")
  end)
  h.assert_true("Reader refreshes after undoing black-hole delete", reader.refresh(reader_bufnr))
  local original = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  local original_notify = vim.notify
  vim.notify = function() end
  for _, keys in ipairs({ "2yic", "2dic", "2cic" }) do
    h.assert_true(keys .. " target cell is found", position_on_cell(reader_bufnr, 3, 2) ~= nil)
    vim.fn.feedkeys(keys, "xt")
    vim.wait(80)
    h.assert_deep_eq(
      keys .. " is rejected without changing the long table",
      vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
      original
    )
    h.assert_eq(keys .. " leaves Reader active", vim.api.nvim_get_current_buf(), reader_bufnr)
  end
  vim.notify = original_notify

  close_and_delete(plugin, source_bufnr)
end)

h.test("typed long-table cic is one undo block, redoable, and repeatable on another cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  local cross_over_line = interaction_table[3]
  vim.bo[source_bufnr].undolevels = -1
  vim.bo[source_bufnr].undolevels = 1000
  h.assert_true("CrossOver type cell is found for cic", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.feedkeys('"acicreplacement\27', "xt")
  vim.wait(80)
  h.assert_eq(
    'long-table "acic stores replaced raw Source in register a',
    vim.fn.getreg("a"),
    "兼容层（基于Wine）[bilibili](https://www.bilibili.com)"
  )
  h.assert_true(
    "typed long-table cic writes one cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1]:find("| **CrossOver** | replacement |", 1, true) ~= nil
  )

  vim.fn.feedkeys("u", "xt")
  vim.wait(80)
  h.assert_eq(
    "one undo restores the complete long-table cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1],
    cross_over_line
  )
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-r>", true, false, true), "xt")
  vim.wait(80)
  h.assert_true(
    "redo restores the complete long-table replacement",
    vim.api.nvim_buf_get_lines(source_bufnr, 2, 3, false)[1]:find("| **CrossOver** | replacement |", 1, true) ~= nil
  )

  reader_bufnr = plugin.reader_preview()
  h.assert_true("Proton type cell is found for dot repeat", position_on_cell(reader_bufnr, 4, 2) ~= nil)
  vim.fn.feedkeys(".", "xt")
  vim.wait(80)
  h.assert_true(
    "dot repeats replacement on the Proton logical cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 3, 4, false)[1]:find("| **Proton** | replacement |", 1, true) ~= nil
  )
  h.assert_eq("logical dot repeat stays in Reader", vim.api.nvim_get_current_buf(), reader_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("native cip remains reachable from inside a long table cell", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
  h.assert_true("CrossOver type cell is found for native cip", position_on_cell(reader_bufnr, 3, 2) ~= nil)
  vim.fn.setreg("a", "native change sentinel")

  vim.fn.feedkeys('"acipparagraph replacement\27', "xt")
  vim.wait(80)

  h.assert_deep_eq(
    "native cip applies Source paragraph semantics rather than cell semantics",
    vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false),
    { "paragraph replacement" }
  )
  h.assert_true(
    'native "acip preserves the selected register prefix',
    vim.fn.getreg("a"):find("方案名称", 1, true) ~= nil
  )
  h.assert_true(
    'native "acip captures the complete Source paragraph',
    vim.fn.getreg("a"):find("CrossOver", 1, true) ~= nil
  )
  h.assert_eq("native cip leaves Reader for Source editing", vim.api.nvim_get_current_buf(), source_bufnr)
  close_and_delete(plugin, source_bufnr)
end)

h.test("common Reader c motions match native Source operations on the long table", function()
  local cases = {
    { label = "ciw", keys = "ciwWORD\27" },
    { label = "cw", keys = "cwWORD\27" },
    { label = "c$", keys = "c$TAIL\27" },
    { label = "cc", keys = "ccROW\27" },
    { label = '"a2cw', keys = '"a2cwPAIR\27' },
  }

  for _, case in ipairs(cases) do
    local plugin, source_bufnr, reader_bufnr = open_reader(72, interaction_table)
    local cell = position_on_cell(reader_bufnr, 3, 2)
    h.assert_true(case.label .. " Reader target cell is found", cell ~= nil)
    local source_cursor = { cell.source_span.start_lnum, cell.source_span.start_col }
    vim.fn.setreg("a", "Reader named sentinel")
    vim.fn.feedkeys(case.keys, "xt")
    vim.wait(80)
    local reader_result = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
    close_and_delete(plugin, source_bufnr)

    local baseline = vim.api.nvim_create_buf(false, true)
    vim.bo[baseline].buftype = "nofile"
    vim.bo[baseline].swapfile = false
    vim.bo[baseline].filetype = "text"
    vim.api.nvim_buf_set_lines(baseline, 0, -1, false, interaction_table)
    vim.api.nvim_set_current_buf(baseline)
    vim.api.nvim_win_set_cursor(0, source_cursor)
    vim.fn.setreg("a", "Source named sentinel")
    vim.fn.feedkeys(case.keys, "xt")
    vim.wait(80)
    local native_result = vim.api.nvim_buf_get_lines(baseline, 0, -1, false)

    h.assert_deep_eq(case.label .. " matches native Source change semantics", reader_result, native_result)
    delete_buffer(baseline)
  end
end)

h.test("Reader cell mappings are configurable and can be disabled", function()
  local plugin, source_bufnr, reader_bufnr = open_reader(72)
  local mappings = vim.api.nvim_buf_get_keymap(reader_bufnr, "n")
  local seen = {}
  for _, mapping in ipairs(mappings) do
    seen[mapping.lhs] = true
  end
  h.assert_true("default c mapping is installed", seen.c)
  h.assert_true("default y prefix is guarded in Reader", seen.y)
  h.assert_true("default d prefix is guarded in Reader", seen.d)
  h.assert_false("complete yic mapping is not installed separately", seen.yic)
  h.assert_false("complete vic mapping is not installed separately", seen.vic)
  h.assert_false("complete dic mapping is not installed separately", seen.dic)
  h.assert_true("Source c proxy keeps the cic compatibility alias", seen.cic)
  h.assert_false("cell put does not shadow native cip by default", seen.cip)
  h.assert_true("Reader installs cell dot repeat", seen["."])
  h.assert_true("cell inner object is installed for operators", vim.fn.maparg("ic", "o", false, true).buffer == 1)
  h.assert_true("cell inner object is installed for Visual", vim.fn.maparg("ic", "x", false, true).buffer == 1)
  position_on_cell(reader_bufnr, 5, 2)
  vim.fn.setreg('"', "")
  vim.fn.feedkeys("yic", "xt")
  vim.wait(80)
  h.assert_eq(
    "mapped yic copies the raw Source cell",
    vim.fn.getreg('"'),
    "[GitHub documentation portal](https://github.com)"
  )
  close_and_delete(plugin, source_bufnr)

  plugin, source_bufnr, reader_bufnr = open_reader(72, nil, {
    mappings = { reader = { cell = { put = "cip" } } },
  })
  mappings = vim.api.nvim_buf_get_keymap(reader_bufnr, "n")
  seen = {}
  for _, mapping in ipairs(mappings) do
    seen[mapping.lhs] = true
  end
  h.assert_true("legacy cip remains available by explicit opt-in", seen.cip)
  close_and_delete(plugin, source_bufnr)

  plugin, source_bufnr, reader_bufnr = open_reader(72)
  plugin.setup({ auto_preview = false, mappings = { reader = { cell = false } } })
  mappings = vim.api.nvim_buf_get_keymap(reader_bufnr, "n")
  seen = {}
  for _, mapping in ipairs(mappings) do
    seen[mapping.lhs] = true
  end
  h.assert_false(
    "cell mappings can be disabled",
    seen.y or seen.d or seen.yic or seen.vic or seen.dic or seen.cic or seen.cip or seen.c
  )
  plugin.close_reader()
  plugin.state.paused_buffers[source_bufnr] = nil
  delete_buffer(source_bufnr)
end)

h.test("guarded operator prefixes support configured leader and control-key suffixes", function()
  local previous_leader = vim.g.mapleader
  vim.g.mapleader = ","
  local plugin, source_bufnr, reader_bufnr = open_reader(72, nil, {
    mappings = {
      reader = {
        cell = {
          yank = "y<leader>c",
          delete = "d<C-x>",
        },
      },
    },
  })
  local raw = "[GitHub documentation portal](https://github.com)"
  h.assert_true("custom guarded yank target is found", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  vim.fn.feedkeys("y,c", "xt")
  vim.wait(80)
  h.assert_eq("custom leader yank copies exact Source", vim.fn.getreg('"'), raw)

  h.assert_true("custom guarded delete target is found", position_on_cell(reader_bufnr, 5, 2) ~= nil)
  local control_x = vim.api.nvim_replace_termcodes("<C-x>", true, false, true)
  vim.fn.feedkeys("d" .. control_x, "xt")
  vim.wait(80)
  h.assert_eq(
    "custom control-key delete changes only the Source cell",
    vim.api.nvim_buf_get_lines(source_bufnr, 4, 5, false)[1],
    "| one |  | a deliberately long note that wraps across several Reader lines |"
  )

  close_and_delete(plugin, source_bufnr)
  vim.g.mapleader = previous_leader
end)
