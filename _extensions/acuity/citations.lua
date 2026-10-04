-- Citeproc renders every citation and the bibliography here, for both formats.
-- On top of that, the first citation of a work adds a short reference to the
-- margin, unless `sidenote-citations: false`, which prints citations in full
-- with an author-date style instead.

local bib, seen, marked = {}, {}, {}

local typst = quarto.doc.is_format("typst")

local margin = true

local function typst_wrap(open, inlines, close)
  local out = pandoc.Inlines({ pandoc.RawInline("typst", open) })
  out:extend(inlines)
  out:insert(pandoc.RawInline("typst", close))
  return out
end

-- A zero-width anchor on the first citation of a work
local function mention_anchor(id)
  if typst then
    return pandoc.RawInline("typst", ('#box()#label("cite-%s")'):format(id))
  end
  return pandoc.Span({}, pandoc.Attr("cite-" .. id))
end

local function anchor(el)
  local out = pandoc.List()
  for _, c in ipairs(el.citations) do
    if bib[c.id] and not marked[c.id] then
      marked[c.id] = true
      out:insert(mention_anchor(c.id))
    end
  end
  out:insert(el)
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

-- Data is provenance rather than an argument, so it is cited in the text and in
-- the bibliography but kept out of the margin, which belongs to the work the
-- text engages with.
local NO_MARGIN = { dataset = true }

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

-- "[1] Author, 'Title', 2019." for the margin, or nothing if there is no title.
local function margin_ref(c)
  local r = bib[c.id]
  if not r.title then return nil end
  -- An empty Cite of the same key takes the number citeproc assigns.
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

local function expand(el)
  local out = anchor(el)
  if not margin then return out end
  for _, c in ipairs(el.citations) do
    if bib[c.id] and not seen[c.id] and not NO_MARGIN[bib[c.id].type] then
      seen[c.id] = true
      out:insert(margin_ref(c))
    end
  end
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

-- `^[@key]` sits against the word it follows, which suits a raised marker. A
-- citation printed in full is part of the sentence and needs a space, an
-- unbreakable one so the citation is never stranded at the start of a line.
local function spaced(inlines)
  if not margin then inlines:insert(1, pandoc.Str("\u{00A0}")) end
  return inlines
end

-- `^[@key]` means "cite this", so render it as a citation and not as a note.
-- Any other note keeps its citations, anchored so that an entry can point back
-- at them.
local CITES = {
  traverse = "topdown",
  Note = function(n)
    local cite = lone_cite(n)
    if cite then return spaced(expand(cite)), false end
    return n:walk({ Cite = anchor }), false
  end,
  Header = function(h) return h, false end,
  Span = function(s)
    if s.classes:includes("no-footnote") then return s, false end
  end,
  Cite = function(el) return expand(el), false end,
}

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
  local content = span.content
  if typst then content = typst_wrap("#parbreak()", content, "") end
  return pandoc.Span(content, pandoc.Attr("", { "inline-ref" }))
end

local function ref_para(span)
  return pandoc.Para(pandoc.Span(span.content, pandoc.Attr("", { "inline-ref" })))
end

-- Everywhere else the reference becomes a margin note of its own.
local function ref_note(span)
  return pandoc.Span(typst_wrap("#sidenote(numbering: none)[", span.content, "]"))
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

-- Only citeproc's rendering of a citation is kept: the Typst writer would cite
-- a Cite itself, and Quarto's citeproc would render it a second time. In the
-- margin style the number is a marker, so it is raised.
local function marker(c)
  if typst then
    if not margin then return c.content end
    return typst_wrap("#super[", c.content, "]")
  end
  -- What Quarto's reference popup looks for.
  local content = c.content:walk({
    Link = function(l)
      if l.target:match("^#ref%-") then l.attributes.role = "doc-biblioref" end
      return l
    end,
  })
  local ids = {}
  for _, cit in ipairs(c.citations) do ids[#ids + 1] = cit.id end
  return pandoc.Inlines({ pandoc.Span(content,
    pandoc.Attr("", margin and { "citation" } or {}, { cites = table.concat(ids, " ") })) })
end

-- A numeric style prints only the number, so `@key` in a sentence gets the
-- authors' names in front of it.
local function rendered(c)
  local first = c.citations[1]
  local who = margin and first.mode == "AuthorInText" and authors_of(bib[first.id])
  if not who then return marker(c) end
  return pandoc.Inlines(who .. " ") .. marker(c)
end

-- An entry points back at the first place its work is cited, from its number.
local function backlinked(div)
  local key = div.identifier:match("^ref%-(.+)$")
  if not (key and marked[key]) then return nil end
  return div:walk({
    Span = function(s)
      if not s.classes:includes("csl-left-margin") then return nil end
      -- Typst reads a "1. " inside a link as a numbered list, so the space stays out.
      local number, space = pandoc.List(s.content), pandoc.List()
      while #number > 0 and number[#number].t == "Space" do
        space:insert(1, table.remove(number))
      end
      if #number == 0 then return nil end
      local link = pandoc.Link(number, "#cite-" .. key, "",
        pandoc.Attr("", { "csl-backlink" }, { role = "doc-backlink" }))
      local linked = pandoc.List({ link }):extend(space)
      -- HTML sets the number beside the entry by the class it carries, so the
      -- span stays.
      if not typst then return pandoc.Span(linked, s.attr) end
      return linked
    end,
  })
end

-- Material that is used rather than argued with is listed apart from the
-- literature, each kind in a section of its own and in the order given here.
local CATEGORIES = {
  { type = "dataset", title = "Data", mark = "D" },
  { type = "software", title = "Software", mark = "S" },
}

local function category_of(key)
  if not bib[key] then return nil end
  for i, category in ipairs(CATEGORIES) do
    if bib[key].type == category.type then return i end
  end
end

-- A section gets the whole width, with the heading outside the wide block
-- because a level-1 heading breaks the page.
local function section(title, entries, attr)
  if not typst then
    -- Quarto's own class, which places the list on the page grid: a width of
    -- its own cannot meet the grid lines, and overhangs the margin column.
    local classes = pandoc.List(attr.classes)
    classes:insert("column-page-right")
    return pandoc.Blocks({
      -- Make the sections have link in TOC
      pandoc.Header(1, pandoc.Str(title), pandoc.Attr("sec-" .. attr.identifier)),
      pandoc.Div(entries, pandoc.Attr(attr.identifier, classes, attr.attributes)),
    })
  end
  return pandoc.Blocks({
    pandoc.RawBlock("typst", ("#heading(level: 1)[%s]\n"):format(title)
      .. "#wideblock[#set par(hanging-indent: 1.5em, spacing: 0.9em)"),
    pandoc.Div(entries, attr),
    pandoc.RawBlock("typst", "]"),
  })
end

-- Citeproc numbers the whole bibliography in one series. Each section counts
-- from one instead, in its entries and in the citations of them. Only the
-- first number of an element is relabelled, and only if it is the entry's
-- number, so that a year in an author-date citation stays.
local function relabel(el, from, to)
  local done = false
  return el:walk({
    Str = function(str)
      local n = not done and str.text:match("%d+")
      if not n then return nil end
      done = true
      if n ~= from then return nil end
      return pandoc.Str((str.text:gsub("%d+", to, 1)))
    end,
  })
end

-- Splits the bibliography, and records the label each entry has in its section.
local function references(div, label)
  local listed = {}
  for i = 0, #CATEGORIES do listed[i] = pandoc.List() end
  for _, entry in ipairs(div.content) do
    local key = entry.t == "Div" and entry.identifier:match("^ref%-(.+)$")
    local i = key and category_of(key) or 0
    if key then
      local from = pandoc.utils.stringify(entry):match("%d+")
      local to = (i > 0 and CATEGORIES[i].mark or "") .. (#listed[i] + 1)
      label[key] = { from = from, to = to }
      entry = relabel(entry, from, to)
    end
    listed[i]:insert(entry)
  end
  local out = section("References", listed[0], div.attr)
  for i, category in ipairs(CATEGORIES) do
    if #listed[i] > 0 then
      -- The same classes as the list it came out of, so it is styled alike.
      out:extend(section(category.title, listed[i],
        pandoc.Attr("refs-" .. category.type, div.attr.classes, div.attr.attributes)))
    end
  end
  return out
end

local function relabel_marks(blocks, label)
  return blocks:walk({
    Link = function(l)
      local key = l.target:match("^#ref%-(.+)$")
      if key and label[key] then return relabel(l, label[key].from, label[key].to) end
    end,
  })
end

-- Quarto resolves a crossref only after this filter, so `@fig-1` is still a
-- citation here and citeproc would print it as a missing entry. A key the
-- bibliography does not know is a crossref, so it is set aside and put back
-- once the bibliography is built.
local function take_crossrefs(doc)
  local kept = pandoc.List()
  doc.blocks = doc.blocks:walk({
    Cite = function(c)
      for _, cit in ipairs(c.citations) do
        if bib[cit.id] then return nil end
      end
      kept:insert(c)
      return pandoc.Span({}, pandoc.Attr("acuity-crossref-" .. #kept))
    end,
  })
  return doc, kept
end

local function put_crossrefs(doc, kept)
  doc.blocks = doc.blocks:walk({
    Span = function(s)
      local i = s.identifier:match("^acuity%-crossref%-(%d+)$")
      if i then return kept[tonumber(i)] end
    end,
  })
  return doc
end

-- Built here rather than by Quarto, so that both formats can split the
-- bibliography and link it back to the text: no filter runs late enough to see
-- the one Quarto would write.
local function citeproc_bibliography(doc)
  local crossrefs
  doc, crossrefs = take_crossrefs(doc)
  doc.meta.csl = doc.meta.csl or doc.meta[margin and "acuity-csl" or "acuity-plain-csl"]
  doc.meta["link-citations"] = true
  doc = pandoc.utils.citeproc(doc)
  -- Left in place, either key would have the bibliography printed a second time.
  doc.meta.csl, doc.meta.bibliography = nil, nil
  local label = {}
  doc = doc:walk({
    Cite = rendered,
    Div = function(div)
      if div.identifier == "refs" then return references(div, label) end
      return backlinked(div)
    end,
  })
  doc.blocks = relabel_marks(doc.blocks, label)
  return put_crossrefs(doc, crossrefs)
end

return {
  {
    -- The body only: a `nocite` key in the metadata is a work to list, not a
    -- mention to anchor.
    Pandoc = function(doc)
      for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = r end
      margin = doc.meta["sidenote-citations"] ~= false
      doc.blocks = doc.blocks:walk(CITES)
      return doc
    end,
  },
  {
    Div = block_refs,
    FloatRefTarget = float_refs,
  },
  {
    Pandoc = function(doc)
      -- Whatever is left was cited from body text, so it becomes a note.
      if typst then
        doc.blocks = doc.blocks:walk({
          Span = function(s)
            if s.classes:includes("column-margin") then return ref_note(s) end
          end,
        })
      end
      return citeproc_bibliography(doc)
    end,
  },
}
