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
  local marker = ("#cite(%s%s%s)"):format(key_of(c),
    c.mode == "AuthorInText" and ', form: "prose"' or "",
    locator == "" and "" or (", supplement: [%s]"):format(locator))
  -- Raise the marker above the line unless the sentence already names the author.
  if c.mode ~= "AuthorInText" then marker = ("#super[%s]"):format(marker) end
  out:insert(pandoc.RawInline("typst", marker))
  return out
end

local function year(date)
  local parts = date and date["date-parts"]
  return parts and parts[1] and parts[1][1]
end

local WEB = { webpage = true, ["post-weblog"] = true, post = true }

-- The bibliography dates a web page by the visit rather than by publication, so
-- report whichever date the entry itself shows and never the other.
-- Returns "issued" or "accessed" and the year, or nothing if the entry has no date.
local function date_of(r)
  local visited = year(r.accessed)
  if WEB[r.type] and visited then return "accessed", visited end
  if year(r.issued) then return "issued", year(r.issued) end
  if visited then return "accessed", visited end
end

local function dated(c)
  local kind, y = date_of(bib[c.id])
  if not kind then return "" end
  -- Let the style format the publication year, since it owns how one looks.
  if kind == "issued" then return (', #cite(%s, form: "year")'):format(key_of(c)) end
  return (", accessed %s"):format(y)
end

-- Builds "[1] Author, 'Title', 2019." for the margin, or the full entry if there is no title.
local function short_ref(c)
  local key = key_of(c)
  local title = bib[c.id].title
  if not title then return ('#cite(%s, form: "full")'):format(key) end
  -- The number is raised to match the marker in the text and spaced like a footnote marker.
  return ([[#super[#cite(%s)]#h(0.25em)#cite(%s, form: "author"), '%s'%s.]])
    :format(key, key, markup(title), dated(c))
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
      -- Marked for a later pass, which either turns it into a note or leaves it
      -- in the block it came from, depending on where the citation is.
      notes:insert(pandoc.Span({ pandoc.RawInline("typst", short_ref(c)) },
        pandoc.Attr("", { "column-margin" })))
    end
  end
  -- Notes go after all the citations, because one in between stops Typst joining "[1], [2]".
  out:extend(notes)
  return out
end

-- Returns the citation inside `^[@key]`, or nil if the footnote holds anything else.
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
  -- `^[@key]` asks for a marker, so drop the author's name from the sentence.
  local cites = pandoc.List()
  for _, c in ipairs(found.citations) do
    c.mode = "NormalCitation"
    cites:insert(c)
  end
  return pandoc.Cite(found.content, cites)
end

-- "Daniela R." -> "D. R.", the way the bibliography style writes given names.
local function initials(given)
  local out = {}
  for word in pandoc.utils.stringify(given):gmatch("%S+") do
    out[#out + 1] = word:sub(1, 1) .. "."
  end
  return table.concat(out, " ")
end

local function authors_of(r)
  local names = {}
  for _, a in ipairs(r.author or {}) do
    if a.literal then
      names[#names + 1] = pandoc.utils.stringify(a.literal)
    else
      local given = a.given and initials(a.given) or ""
      names[#names + 1] = (given == "" and "" or given .. " ") .. pandoc.utils.stringify(a.family)
    end
  end
  if #names == 0 then return nil end
  if #names == 1 then return names[1] end
  if #names == 2 then return names[1] .. " and " .. names[2] end
  return table.concat(names, ", ", 1, #names - 1) .. ", and " .. names[#names]
end

-- The same short reference the Typst side builds, as inlines for the margin.
local function margin_ref(c)
  local r = bib[c.id]
  if not r.title then return nil end
  -- An empty Cite of the same key reuses the number citeproc assigned, instead
  -- of a second count kept here that could drift from it.
  local out = pandoc.List({
    pandoc.Cite({}, { pandoc.Citation(c.id, "NormalCitation") }),
    pandoc.Space(),
  })
  local who = authors_of(r)
  if who then out:extend({ pandoc.Str(who .. ","), pandoc.Space() }) end
  local title = pandoc.List(r.title)
  local url = r.url or r.URL
  if url then title = pandoc.List({ pandoc.Link(title, pandoc.utils.stringify(url)) }) end
  out:insert(pandoc.Str("\u{2018}"))
  out:extend(title)
  out:insert(pandoc.Str("\u{2019}"))
  local kind, y = date_of(r)
  out:insert(pandoc.Str(kind and (", %s%s."):format(kind == "accessed" and "accessed " or "", y) or "."))
  return pandoc.Span(out, pandoc.Attr("", { "column-margin" }))
end

-- HTML keeps citeproc's citation and adds a margin reference after the first one.
local function expand_html(el)
  local out = pandoc.List({ el })
  for _, c in ipairs(el.citations) do
    if bib[c.id] and not seen[c.id] then
      seen[c.id] = true
      out:insert(margin_ref(c))
    end
  end
  return out
end

local typst = quarto.doc.is_format("typst")

-- Pulls the marked references out of an element, leaving the markers in place.
local function take_refs(el)
  local refs = pandoc.List()
  el = el:walk({
    Span = function(s)
      if s.classes:includes("column-margin") then
        refs:insert(s)
        return {}
      end
    end,
  })
  return el, refs
end

-- A reference cited from the margin stays in the block that cited it, because a
-- note inside a note has nowhere to go.
local function ref_inline(span)
  if typst then
    return pandoc.RawInline("typst", "#parbreak()" .. span.content[1].text)
  end
  return pandoc.Span(span.content, pandoc.Attr("", { "inline-ref" }))
end

local function ref_para(span)
  if typst then return pandoc.Para(span.content) end
  return pandoc.Para(pandoc.Span(span.content, pandoc.Attr("", { "inline-ref" })))
end

-- Everywhere else the reference becomes a margin note of its own.
local function ref_note(span)
  if typst then
    return pandoc.RawInline("typst",
      ('#sidenote(numbering: none)[%s]'):format(span.content[1].text))
  end
  return span
end

-- A margin block keeps the references for the citations it makes.
local function block_refs(div)
  local classes = div.classes
  if not (classes:includes("column-margin") or classes:includes("sideblock")
          or classes:includes("notefigure")) then
    return nil
  end
  local out, refs = take_refs(div)
  if #refs == 0 then return nil end
  for _, ref in ipairs(refs) do out.content:insert(ref_para(ref)) end
  return out
end

-- captions.lua has already decided where every caption goes. In Typst it marks
-- a margin caption as a top caption, which the template turns into a note.
local function in_margin(float)
  local location = float.attributes["cap-location"]
  return location == "margin" or (typst and location == "top")
    or float.classes:includes("column-margin")
    or float.classes:includes("notefigure")
end

-- A float's references go inside its caption when the caption is in the margin.
-- Outside it, HTML would make Quarto lay the figcaption out as a grid, where the
-- caption text, a bare text node rather than an element, drops into the first
-- and narrowest column; Typst would get a note inside a note. A caption that
-- stays under the figure is body text, so its references become notes as usual.
local function float_refs(float, float_node)
  if not float.caption_long then return nil end
  local caption, refs = take_refs(float.caption_long)
  if #refs == 0 then return nil end
  float.caption_long = caption
  local content = float.caption_long.content
  if in_margin(float) then
    for _, ref in ipairs(refs) do content:insert(ref_inline(ref)) end
    return float
  end
  if typst then
    for _, ref in ipairs(refs) do content:insert(ref_note(ref)) end
    return float
  end
  local block = pandoc.List()
  for _, ref in ipairs(refs) do block:insert(ref_para(ref)) end
  return pandoc.Blocks({
    float_node,
    pandoc.Div(block, pandoc.Attr("", { "column-margin" })),
  })
end

if not quarto.doc.is_format("typst") then
  return {
    {
      Pandoc = function(doc)
        for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = r end
      end,
    },
    {
      traverse = "topdown",
      Note = function(n)
        local cite = lone_cite(n)
        if cite then return expand_html(cite), false end
        return n, false
      end,
      Cite = function(el) return expand_html(el), false end,
    },
    {
      Div = block_refs,
      FloatRefTarget = float_refs,
    },
  }
end

return {
  {
    Pandoc = function(doc)
      for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = r end
    end,
  },
  {
    traverse = "topdown",
    -- `^[@key]` means "cite this", so render it as a citation and not as a numbered note.
    Note = function(n)
      local cite = lone_cite(n)
      if cite then
        local out = expand(cite)
        if out then return out, false end
      end
      return n, false
    end,
    Header = function(h) return h, false end,
    Span = function(s)
      if s.classes:includes("no-footnote") then return s, false end
    end,
    Cite = function(el)
      return expand(el), false
    end,
  },
  {
    Div = block_refs,
    FloatRefTarget = float_refs,
  },
  {
    -- Whatever is left was cited from body text, so it becomes a note.
    Span = function(s)
      if s.classes:includes("column-margin") then return ref_note(s) end
    end,
  },
}
