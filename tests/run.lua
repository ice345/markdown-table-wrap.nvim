local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

local specs = {
  "tests.spec.markdown_spec",
  "tests.spec.parser_spec",
  "tests.spec.width_spec",
  "tests.spec.wrap_spec",
  "tests.spec.render_spec",
  "tests.spec.theme_spec",
  "tests.spec.config_spec",
  "tests.spec.inline_spec",
  "tests.spec.reader_spec",
  "tests.spec.context_spec",
  "tests.spec.actions_spec",
  "tests.spec.links_spec",
  "tests.spec.multiwindow_spec",
  "tests.spec.inspect_spec",
  "tests.spec.mappings_spec",
  "tests.spec.nav_spec",
  "tests.spec.mode_spec",
  "tests.spec.system_spec",
  "tests.spec.lifecycle_spec",
  "tests.spec.v04_spec",
}

for _, spec in ipairs(specs) do
  require(spec)
end

require("tests.helpers").finish()
