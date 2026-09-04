-- Minimal fixtures derived from the GitHub Flavored Markdown table extension
-- examples: https://github.github.com/gfm/#tables-extension-
return {
  source = "GitHub Flavored Markdown Spec, Tables (extension)",
  cases = {
    {
      id = "gfm-198-basic",
      classification = "supported",
      lines = { "| foo | bar |", "| --- | --- |", "| baz | bim |" },
      columns = 2,
      rows = 1,
    },
    {
      id = "gfm-199-alignment",
      classification = "supported",
      lines = { "| abc | defghi |", ":--- | :----:", "bar | baz" },
      columns = 2,
      rows = 1,
    },
    {
      id = "gfm-200-escaped-and-code-pipes",
      classification = "supported",
      lines = { "| f\\|oo | `b|ar` |", "| --- | --- |", "| baz | bim |" },
      columns = 2,
      rows = 1,
    },
    {
      id = "gfm-201-delimiter-mismatch",
      classification = "invalid",
      lines = { "| abc | def |", "| --- |", "| bar | baz |" },
    },
    {
      id = "gfm-202-body-normalization",
      classification = "supported",
      lines = { "| abc | def |", "| --- | --- |", "| bar |", "| bar | baz | boo |" },
      columns = 2,
      rows = 2,
    },
    {
      id = "container-prefix-blockquote",
      classification = "supported",
      lines = { "> | abc | def |", "> | --- | --- |", "> | bar | baz |" },
      columns = 2,
      rows = 1,
    },
    {
      id = "container-prefix-list",
      classification = "unsupported",
      lines = { "- | abc | def |", "  | --- | --- |", "  | bar | baz |" },
      reason = "list continuation and indentation rules do not yet provide lossless Source spans",
    },
    {
      id = "fenced-table-shaped-text",
      classification = "invalid",
      lines = { "```markdown", "| abc | def |", "| --- | --- |", "```" },
    },
    {
      id = "pipe-like-prose",
      classification = "invalid",
      lines = { "abc | def", "not a delimiter | still prose" },
    },
    {
      id = "compact-separator-one-dash",
      classification = "supported",
      lines = { "| a | b |", "|-|-|", "| 1 | 2 |" },
      columns = 2,
      rows = 1,
    },
    {
      id = "compact-separator-two-dashes",
      classification = "supported",
      lines = { "| a | b |", "|--|--|", "| 1 | 2 |" },
      columns = 2,
      rows = 1,
    },
    {
      id = "compact-separator-without-outer-pipes",
      classification = "supported",
      lines = { "a|b|c", "-|-|-", "1|2|3" },
      columns = 3,
      rows = 1,
    },
    {
      id = "compact-separator-alignment",
      classification = "supported",
      lines = { "| left | center | right |", "|:-|:-:|--:|" },
      columns = 3,
      rows = 0,
    },
    {
      id = "heading-boundary",
      classification = "boundary",
      lines = { "| abc | def |", "| --- | --- |", "| bar | baz |", "# next | block" },
      end_lnum = 3,
    },
    {
      id = "definition-boundary",
      classification = "boundary",
      lines = { "| abc | def |", "| --- | --- |", "| bar | baz |", "[ref]: https://example.com/a|b" },
      end_lnum = 3,
    },
    {
      id = "html-block-boundary",
      classification = "boundary",
      lines = { "| abc | def |", "| --- | --- |", "| bar | baz |", "<div>next | block</div>" },
      end_lnum = 3,
    },
  },
}
