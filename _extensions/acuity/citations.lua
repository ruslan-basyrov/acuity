local bib, seen = {}, {}

local function markup(inlines)
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "typst"):gsub("%s+$", "")
end

local function render(c, first)
  local key = ('label("%s")'):format(c.id:gsub('[\\"]', "\\%0"))
  local locator = markup(c.suffix):gsub("^[,%s]*", "")
  local out = pandoc.List(c.prefix)
  if #out > 0 then out:insert(pandoc.Space()) end
  local raw
  if first then
    raw = (c.mode == "AuthorInText" and ('#cite(%s, form: "prose")'):format(key) or "")
      .. ('#footnote[#cite(%s, form: "full")%s]'):format(key, locator == "" and "" or " " .. locator)
  else
    raw = ("#cite(%s%s%s)"):format(key,
      c.mode == "AuthorInText" and ', form: "prose"' or "",
      locator == "" and "" or (", supplement: [%s]"):format(locator))
  end
  out:insert(pandoc.RawInline("typst", raw))
  return out
end

return {
  {
    Pandoc = function(doc)
      for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = true end
    end,
  },
  {
    traverse = "topdown",
    Note = function(n) return n, false end,
    Header = function(h) return h, false end,
    Div = function(d)
      if d.classes:includes("sideblock") then return d, false end
    end,
    Span = function(s)
      if s.classes:includes("no-footnote") then return s, false end
    end,
    Cite = function(el)
      for _, c in ipairs(el.citations) do
        if not bib[c.id] then return nil, false end
      end
      local out, prev_note = pandoc.List(), false
      for _, c in ipairs(el.citations) do
        local first = not seen[c.id]
        seen[c.id] = true
        if prev_note and first then out:insert(pandoc.RawInline("typst", "#super[,]")) end
        out:extend(render(c, first))
        prev_note = first
      end
      return out, false
    end,
  },
}
