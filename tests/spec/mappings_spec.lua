local h = require("tests.helpers")

local function flush_typeahead()
  vim.api.nvim_feedkeys("", "x", false)
end

h.test("mapping invocation supports callbacks strings expressions and remaps", function()
  local mappings = require("markdown-table-wrap.mappings")
  h.with_buffer({ "abc" }, function(bufnr)
    local callback_calls = 0
    vim.keymap.set("n", "Q", function()
      callback_calls = callback_calls + 1
    end, { buffer = bufnr })
    h.assert_true("callback mapping invokes", mappings.invoke(mappings.get(bufnr, "Q", "n"), { context_bufnr = bufnr }))
    h.assert_eq("callback mapping runs once", callback_calls, 1)

    vim.g.markdown_table_wrap_string_calls = 0
    vim.keymap.set("n", "Q", "<Cmd>let g:markdown_table_wrap_string_calls += 1<CR>", {
      buffer = bufnr,
      noremap = true,
    })
    h.assert_true("string mapping invokes", mappings.invoke(mappings.get(bufnr, "Q", "n"), { context_bufnr = bufnr }))
    flush_typeahead()
    h.assert_eq("string rhs executes", vim.g.markdown_table_wrap_string_calls, 1)

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.keymap.set("n", "Q", function()
      return "<Right>"
    end, { buffer = bufnr, expr = true, replace_keycodes = true })
    h.assert_true("expression callback invokes", mappings.invoke(mappings.get(bufnr, "Q", "n")))
    flush_typeahead()
    h.assert_eq("replace_keycodes expression moves cursor", vim.api.nvim_win_get_cursor(0)[2], 1)

    local remap_calls = 0
    vim.keymap.set("n", "Z", function()
      remap_calls = remap_calls + 1
    end, { buffer = bufnr })
    vim.keymap.set("n", "Q", "Z", { buffer = bufnr, remap = true })
    local remap = mappings.get(bufnr, "Q", "n")
    h.assert_eq("remap is captured as recursive", remap.noremap, 0)
    h.assert_true("recursive mapping invokes", mappings.invoke(remap))
    flush_typeahead()
    h.assert_eq("recursive rhs reaches delegated mapping", remap_calls, 1)
  end)
end)

h.test("mapping restoration preserves expression semantics and replace_keycodes", function()
  local mappings = require("markdown-table-wrap.mappings")
  local expr_calls = 0
  _G.__markdown_table_wrap_mapping_expr = function()
    expr_calls = expr_calls + 1
    return "l"
  end

  h.with_buffer({ "abc" }, function(bufnr)
    vim.keymap.set("n", "Q", "v:lua.__markdown_table_wrap_mapping_expr()", {
      buffer = bufnr,
      expr = true,
      replace_keycodes = false,
      remap = true,
    })
    local original = mappings.get(bufnr, "Q", "n")
    vim.keymap.set("n", "Q", "h", { buffer = bufnr })
    h.assert_true("mapping restores", mappings.restore(bufnr, "Q", "n", original))
    local restored = mappings.get(bufnr, "Q", "n")
    h.assert_eq("restored mapping remains expression", restored.expr, 1)
    h.assert_eq("restored mapping remains recursive", restored.noremap, 0)
    h.assert_true(
      "restored mapping preserves replace_keycodes when Neovim reports it",
      restored.replace_keycodes == nil or restored.replace_keycodes == original.replace_keycodes
    )
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal Q")
    h.assert_eq("restored expression executes", expr_calls, 1)
    h.assert_eq("restored expression result is applied", vim.api.nvim_win_get_cursor(0)[2], 1)
  end)

  _G.__markdown_table_wrap_mapping_expr = nil
end)
