if vim.g.loaded_markdown_table_wrap == 1 then
  return
end

vim.g.loaded_markdown_table_wrap = 1

require("markdown-table-wrap").setup()
