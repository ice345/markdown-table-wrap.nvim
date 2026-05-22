if vim.g.loaded_markdown_table_wrap == 1 then
  return
end

vim.g.loaded_markdown_table_wrap = 1

local plugin = require("markdown-table-wrap")

if not plugin.state.did_setup then
  plugin.setup()
end
