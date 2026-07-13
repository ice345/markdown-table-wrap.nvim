local h = require("tests.helpers")

h.test("markdown inline token parsing", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("`code` **bold** *italic* ~~strike~~ ==mark== [link](url)")
  local kinds = {}

  for _, span in ipairs(parsed.spans) do
    kinds[span.kind] = true
  end

  h.assert_eq("inline text", parsed.text, "code bold italic strike mark link")
  h.assert_true("code span", kinds.code)
  h.assert_true("bold span", kinds.bold)
  h.assert_true("italic span", kinds.italic)
  h.assert_true("strike span", kinds.strike)
  h.assert_true("mark span", kinds.mark)
  h.assert_true("link span", kinds.link)
end)

h.test("markdown parses link variants and icons", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed =
    markdown.parse_inline("[youtube](https://www.youtube.com) (bili)[https://bilibili.com] [[Wiki]] ![alt](image.png)")

  local kinds = {}
  local link_urls = {}
  for _, span in ipairs(parsed.spans) do
    kinds[span.kind] = span
    if span.kind == "link" then
      link_urls[span.url] = true
    end
  end

  h.assert_true("standard link", kinds.link ~= nil)
  h.assert_true("standard link url", link_urls["https://www.youtube.com"])
  h.assert_true("reversed link url", link_urls["https://bilibili.com"])
  h.assert_true("wiki link", kinds.wiki_link ~= nil)
  h.assert_true("image link", kinds.image ~= nil)

  local with_icons = markdown.apply_link_icons(parsed, {
    link = {
      wiki = { icon = "W " },
      image = "I ",
      custom = {
        youtube = { pattern = "youtube", icon = "Y " },
        bilibili = { pattern = "bilibili", icon = "B " },
      },
    },
  })

  h.assert_true("youtube icon", with_icons.text:find("Y youtube", 1, true) ~= nil)
  h.assert_true("bilibili icon", with_icons.text:find("B bili", 1, true) ~= nil)
  h.assert_true("wiki icon", with_icons.text:find("W Wiki", 1, true) ~= nil)
  h.assert_true("image icon", with_icons.text:find("I alt", 1, true) ~= nil)

  local extracted =
    markdown.extract_links("[YouTube](https://youtube.com) (Bili)[https://bilibili.com] ![Alt](image.png)")
  h.assert_eq("extract link count", #extracted, 3)
  h.assert_eq("extract first url", extracted[1].url, "https://youtube.com")
  h.assert_eq("extract reversed url", extracted[2].url, "https://bilibili.com")
  h.assert_eq("extract image url", extracted[3].url, "image.png")
end)

h.test("markdown parses multi-backtick inline code", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("``a|b``")

  h.assert_eq("multi-backtick display text", parsed.text, "a|b")
  h.assert_eq("multi-backtick kind", parsed.spans[1].kind, "code")
end)

h.test("markdown hard breaks", function()
  local markdown = require("markdown-table-wrap.markdown")
  h.assert_eq("br break", markdown.inline_to_text("a<br>b"), "a\nb")
  h.assert_eq("br slash break", markdown.inline_to_text("a<br/>b"), "a\nb")
end)

h.test("markdown extracts links from parsed cells", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("[youtube](https://www.youtube.com)")
  local links = markdown.extract_links(parsed)

  h.assert_eq("parsed cell link count", #links, 1)
  h.assert_eq("parsed cell link text", links[1].text, "youtube")
  h.assert_eq("parsed cell link url", links[1].url, "https://www.youtube.com")
end)
