local bib, seen = {}, {}

local function markup(inlines)
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "typst"):gsub("%s+$", "")
end

local function key_of(c)
  return ('label("%s")'):format(c.id:gsub('[\\"]', "\\%0"))
end

local function render(c)
  local locator = markup(c.suffix):gsub("^[,%s]*", "")
  local out = pandoc.List(c.prefix)
  if #out > 0 then out:insert(pandoc.Space()) end
  out:insert(pandoc.RawInline("typst", ("#cite(%s%s%s)"):format(key_of(c),
    c.mode == "AuthorInText" and ', form: "prose"' or "",
    locator == "" and "" or (", supplement: [%s]"):format(locator))))
  return out
end

-- Renders a citation, or returns nil if any key is missing from the bibliography.
local function expand(el)
  for _, c in ipairs(el.citations) do
    if not bib[c.id] then return nil end
  end
  local out, notes = pandoc.List(), pandoc.List()
  for _, c in ipairs(el.citations) do
    out:extend(render(c))
    if not seen[c.id] then
      seen[c.id] = true
      -- The note has no number of its own, so the reference number is the only one.
      notes:insert(pandoc.RawInline("typst",
        ('#sidenote(numbering: none)[#cite(%s, form: "full")]'):format(key_of(c))))
    end
  end
  -- Notes go after every citation because one in between stops Typst joining "[1], [2]".
  out:extend(notes)
  return out
end

-- Returns the citation inside `^[@key]`, or nil if the footnote says anything else.
local function lone_cite(n)
  local blocks = n.content
  if #blocks ~= 1 or (blocks[1].t ~= "Para" and blocks[1].t ~= "Plain") then return nil end
  local found
  for _, inline in ipairs(blocks[1].content) do
    if inline.t == "Cite" then
      if found then return nil end
      found = inline
    elseif inline.t ~= "Space" and inline.t ~= "SoftBreak" then
      return nil
    end
  end
  if not found then return nil end
  -- `^[@key]` asks for a marker, so the author's name does not belong in the sentence.
  local cites = pandoc.List()
  for _, c in ipairs(found.citations) do
    c.mode = "NormalCitation"
    cites:insert(c)
  end
  return pandoc.Cite(found.content, cites)
end

return {
  {
    Pandoc = function(doc)
      for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = true end
    end,
  },
  {
    traverse = "topdown",
    -- `^[@key]` means "cite this", so render it as a citation and not as a numbered remark.
    Note = function(n)
      local cite = lone_cite(n)
      if cite then
        local out = expand(cite)
        if out then return out, false end
      end
      return n, false
    end,
    Header = function(h) return h, false end,
    Div = function(d)
      if d.classes:includes("sideblock") then return d, false end
    end,
    Span = function(s)
      if s.classes:includes("no-footnote") then return s, false end
    end,
    Cite = function(el)
      return expand(el), false
    end,
  },
}
