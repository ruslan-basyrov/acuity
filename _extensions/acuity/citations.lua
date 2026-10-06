-- Citeproc renders every citation and the bibliography here, for both formats.
-- On top of that, the first citation of a work adds a short reference to the
-- margin, unless `sidenote-citations: false`, which prints citations in full
-- with an author-date style instead.

local typst = quarto.doc.is_format("typst")

local margin = true

-- The cited works by key, the works whose first mention has an anchor, the
-- works that have a margin reference, and the label of each entry.
local bib, marked, seen, label = {}, {}, {}, {}

local function typst_wrap(open, inlines, close)
  local out = pandoc.Inlines({ pandoc.RawInline("typst", open) })
  out:extend(inlines)
  out:insert(pandoc.RawInline("typst", close))
  return out
end

-- A zero-width anchor on the first mention of a work, for its entry to link
-- back to.
local function anchor(cite)
  local out = pandoc.Inlines({})
  for _, c in ipairs(cite.citations) do
    if bib[c.id] and not marked[c.id] then
      marked[c.id] = true
      out:insert(typst and pandoc.RawInline("typst", ('#box()#label("cite-%s")'):format(c.id))
        or pandoc.Span({}, pandoc.Attr("cite-" .. c.id)))
    end
  end
  out:insert(cite)
  return out
end

local function year(date)
  local parts = date and date["date-parts"]
  return parts and parts[1] and parts[1][1]
end

local WEB = { webpage = true, ["post-weblog"] = true, post = true }

-- ", 2019." or ", accessed 2026.". The bibliography dates a web page by the
-- visit rather than by publication, so report whichever date the entry itself
-- shows and never the other.
local function dated(r)
  local issued, accessed = year(r.issued), year(r.accessed)
  if accessed and (WEB[r.type] or not issued) then return (", accessed %s."):format(accessed) end
  return issued and (", %s."):format(issued) or "."
end

-- "Daniela R." -> "D. R.", the way the bibliography style writes given names.
local function initials(given)
  return (pandoc.utils.stringify(given):gsub("(%S)%S*", "%1."))
end

local function authors_of(r)
  local names = pandoc.List(r.author or {}):map(function(a)
    if a.literal then return pandoc.utils.stringify(a.literal) end
    local given = a.given and initials(a.given) or ""
    return (given == "" and "" or given .. " ") .. pandoc.utils.stringify(a.family)
  end)
  if #names == 0 then return nil end
  if #names <= 2 then return table.concat(names, " and ") end
  return table.concat(names, ", ", 1, #names - 1) .. ", and " .. names[#names]
end

-- "[1] Author, 'Title', 2019." for the margin.
local function margin_ref(id)
  local r = bib[id]
  -- An empty Cite of the same key takes the number citeproc assigns.
  local out = pandoc.Inlines({ pandoc.Cite({}, { pandoc.Citation(id, "NormalCitation") }), pandoc.Space() })
  local who = authors_of(r)
  if who then out:extend({ pandoc.Str(who .. ","), pandoc.Space() }) end
  local title = pandoc.Inlines(r.title)
  local url = r.url or r.URL
  if url then title = pandoc.Inlines({ pandoc.Link(title, pandoc.utils.stringify(url)) }) end
  out:insert(pandoc.Str("\u{2018}"))
  out:extend(title)
  out:insert(pandoc.Str("\u{2019}" .. dated(r)))
  return pandoc.Span(out, pandoc.Attr("", { "column-margin" }))
end

-- Data is provenance rather than an argument, so it is cited in the text and in
-- the bibliography but kept out of the margin, which belongs to the work the
-- text engages with.
local NO_MARGIN = { dataset = true }

-- Anchors a citation and, in the margin style, adds a margin reference for
-- each titled work it is the first to cite.
local function expand(cite)
  local out = anchor(cite)
  if not margin then return out end
  for _, c in ipairs(cite.citations) do
    local r = bib[c.id]
    if r and r.title and not seen[c.id] and not NO_MARGIN[r.type] then
      seen[c.id] = true
      out:insert(margin_ref(c.id))
    end
  end
  return out
end

-- Returns the citation inside `^[@key]`, or nil if the footnote holds anything else.
local function lone_cite(note)
  local block = note.content[1]
  if #note.content ~= 1 or (block.t ~= "Para" and block.t ~= "Plain") then return nil end
  local inlines = block.content:filter(function(el) return el.t ~= "Space" and el.t ~= "SoftBreak" end)
  if #inlines ~= 1 or inlines[1].t ~= "Cite" then return nil end
  -- `^[@key]` asks for a marker, so drop the author's name from the sentence.
  local citations = inlines[1].citations
  for _, c in ipairs(citations) do c.mode = "NormalCitation" end
  return pandoc.Cite(inlines[1].content, citations)
end

-- `^[@key]` means "cite this", so render it as a citation and not as a note.
-- Any other note keeps its citations, anchored so that an entry can point back
-- at them.
local CITES = {
  traverse = "topdown",
  Note = function(note)
    local cite = lone_cite(note)
    if not cite then return note:walk({ Cite = anchor }), false end
    local out = expand(cite)
    -- `^[@key]` sits against the word it follows, which suits a raised marker.
    -- A citation printed in full is part of the sentence and needs a space, an
    -- unbreakable one so the citation is never stranded at the start of a line.
    if not margin then out:insert(1, pandoc.Str("\u{00A0}")) end
    return out, false
  end,
  Header = function(h) return h, false end,
  Span = function(s)
    if s.classes:includes("no-footnote") then return s, false end
  end,
  Cite = function(c) return expand(c), false end,
}

-- Pulls the margin references out of an element, leaving the markers in place.
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
local function ref_inline(ref)
  local content = ref.content
  if typst then content = typst_wrap("#parbreak()", content, "") end
  return pandoc.Span(content, pandoc.Attr("", { "inline-ref" }))
end

local function ref_para(ref)
  return pandoc.Para(pandoc.Span(ref.content, pandoc.Attr("", { "inline-ref" })))
end

-- Everywhere else the reference becomes a margin note of its own.
local function ref_note(ref)
  return pandoc.Span(typst_wrap("#sidenote(numbering: none)[", ref.content, "]"))
end

-- The classes of a block in the margin.
local MARGIN = { ["column-margin"] = true, sideblock = true, notefigure = true }

local function in_margin(el)
  return el.classes:find_if(function(c) return MARGIN[c] end)
end

-- A margin block keeps the references for the citations it makes, the ones in
-- the captions of its floats too.
local function block_refs(div)
  if not in_margin(div) then return nil end
  local out, refs = take_refs(div)
  out.content:extend(refs:map(ref_para))
  return out, false
end

-- layout.lua has already decided where every caption goes. In Typst it marks
-- a margin caption as a top caption, which the template turns into a note.
local function caption_in_margin(float)
  local location = float.attributes["cap-location"]
  return location == "margin" or (typst and location == "top") or in_margin(float)
end

-- A float's references go inside its caption when the caption is in the margin.
-- Outside it, HTML would make Quarto lay the figcaption out as a grid, where the
-- caption text, a bare text node rather than an element, drops into the first
-- and narrowest column; Typst would get a note inside a note. A caption that
-- stays under the figure is body text, so its references become notes as usual.
local function float_refs(float, node)
  if not float.caption_long then return nil end
  local caption, refs = take_refs(float.caption_long)
  if #refs == 0 then return nil end
  float.caption_long = caption
  local content = float.caption_long.content
  if caption_in_margin(float) then
    content:extend(refs:map(ref_inline))
  elseif typst then
    content:extend(refs:map(ref_note))
  else
    return pandoc.Blocks({ node, pandoc.Div(refs:map(ref_para), pandoc.Attr("", { "column-margin" })) })
  end
  return float
end

-- Citeproc numbers the whole bibliography in one series. Each section counts
-- from one instead, in its entries and in the citations of them. Only the
-- first number of an element is relabelled, and only if it is the entry's
-- number, so that a year in an author-date citation stays.
local function relabel(el, key)
  local change = label[key]
  if not change then return el end
  local done = false
  return el:walk({
    Str = function(str)
      local n = not done and str.text:match("%d+")
      if not n then return nil end
      done = true
      if n ~= change.from then return nil end
      return pandoc.Str((str.text:gsub("%d+", change.to, 1)))
    end,
  })
end

-- Only citeproc's rendering of a citation is kept: the Typst writer would cite
-- a Cite itself, and Quarto's citeproc would render it a second time. In the
-- margin style the number is a marker, so it is raised.
local function marker(c, content)
  if typst then
    return margin and typst_wrap("#super[", content, "]") or content
  end
  local ids = c.citations:map(function(cit) return cit.id end)
  return pandoc.Inlines({ pandoc.Span(content,
    pandoc.Attr("", margin and { "citation" } or {}, { cites = table.concat(ids, " ") })) })
end

-- A numeric style prints only the number, so `@key` in a sentence gets the
-- authors' names in front of it.
local function rendered(c)
  local content = c.content:walk({
    Link = function(l)
      local key = l.target:match("^#ref%-(.+)$")
      if not key then return nil end
      -- What Quarto's reference popup looks for.
      if not typst then l.attributes.role = "doc-biblioref" end
      return relabel(l, key)
    end,
  })
  local first = c.citations[1]
  local who = margin and first.mode == "AuthorInText" and authors_of(bib[first.id])
  if not who then return marker(c, content) end
  return pandoc.Inlines(who .. " ") .. marker(c, content)
end

-- An entry points back at the first place its work is cited, from its number.
local function backlinked(entry, key)
  if not marked[key] then return entry end
  return entry:walk({
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
local SECTIONS = {
  { id = "refs", title = "References", mark = "" },
  { id = "refs-dataset", type = "dataset", title = "Data", mark = "D" },
  { id = "refs-software", type = "software", title = "Software", mark = "S" },
}

-- A work of a type without a section of its own is literature.
local function section_of(key)
  local kind = bib[key] and bib[key].type
  for i = 2, #SECTIONS do
    if SECTIONS[i].type == kind then return i end
  end
  return 1
end

-- A section gets the whole width, with the heading outside the wide block
-- because a level-1 heading breaks the page.
local function section(title, entries, attr)
  -- The id gives the section its link in the contents.
  local heading = pandoc.Header(1, pandoc.Str(title), pandoc.Attr("sec-" .. attr.identifier))
  if typst then
    return pandoc.Blocks({
      heading,
      pandoc.RawBlock("typst", "#wideblock[#set par(hanging-indent: 1.5em, spacing: 0.9em)"),
      pandoc.Div(entries, attr),
      pandoc.RawBlock("typst", "]"),
    })
  end
  -- Quarto's own class, which places the list on the page grid: a width of
  -- its own cannot meet the grid lines, and overhangs the margin column.
  local classes = pandoc.List(attr.classes)
  classes:insert("column-page-right")
  return pandoc.Blocks({ heading, pandoc.Div(entries, pandoc.Attr(attr.identifier, classes, attr.attributes)) })
end

-- Splits the bibliography, and records the label each entry has in its section.
local function references(div)
  local listed = {}
  for i = 1, #SECTIONS do listed[i] = pandoc.Blocks({}) end
  for _, entry in ipairs(div.content) do
    local key = entry.t == "Div" and entry.identifier:match("^ref%-(.+)$")
    local i = key and section_of(key) or 1
    if key then
      label[key] = {
        from = pandoc.utils.stringify(entry):match("%d+"),
        to = SECTIONS[i].mark .. (#listed[i] + 1),
      }
      entry = backlinked(relabel(entry, key), key)
    end
    listed[i]:insert(entry)
  end
  local out = pandoc.Blocks({})
  for i, s in ipairs(SECTIONS) do
    -- The literature stays where the bibliography is, even when it is empty.
    -- The other sections take the classes of the list they came out of, so
    -- they are styled alike.
    if i == 1 or #listed[i] > 0 then
      out:extend(section(s.title, listed[i], pandoc.Attr(s.id, div.classes, div.attributes)))
    end
  end
  return out
end

-- Quarto resolves a crossref only after this filter, so `@fig-1` is still a
-- citation here and citeproc would print it as a missing entry. A key the
-- bibliography does not know is a crossref, so it is set aside and put back
-- once the citations are rendered.
local function take_crossrefs(blocks)
  local kept = pandoc.List()
  blocks = blocks:walk({
    Cite = function(c)
      for _, cit in ipairs(c.citations) do
        if bib[cit.id] then return nil end
      end
      kept:insert(c)
      return pandoc.Span({}, pandoc.Attr("acuity-crossref-" .. #kept))
    end,
  })
  return blocks, kept
end

local function put_crossrefs(blocks, kept)
  return blocks:walk({
    Span = function(s)
      local i = s.identifier:match("^acuity%-crossref%-(%d+)$")
      if i then return kept[tonumber(i)] end
    end,
  })
end

-- Built here rather than by Quarto, so that both formats can split the
-- bibliography and link it back to the text: no filter runs late enough to see
-- the one Quarto would write. The bibliography comes first, as the citations
-- take the labels of its entries.
local function citeproc_bibliography(doc)
  local crossrefs
  doc.blocks, crossrefs = take_crossrefs(doc.blocks)
  doc.meta.csl = doc.meta.csl or doc.meta[margin and "acuity-csl" or "acuity-plain-csl"]
  doc.meta["link-citations"] = true
  doc = pandoc.utils.citeproc(doc)
  -- Left in place, either key would have the bibliography printed a second time.
  doc.meta.csl, doc.meta.bibliography = nil, nil
  doc.blocks = doc.blocks:walk({
    Div = function(div)
      if div.identifier == "refs" then return references(div) end
    end,
  })
  doc = doc:walk({ Cite = rendered })
  doc.blocks = put_crossrefs(doc.blocks, crossrefs)
  return doc
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
  -- Top down, so that a margin block takes the references of its floats
  -- before float_refs makes them notes inside the note.
  {
    traverse = "topdown",
    Div = block_refs,
    FloatRefTarget = float_refs,
    -- Whatever is left was cited from body text, so it becomes a note.
    Span = function(s)
      if typst and s.classes:includes("column-margin") then return ref_note(s) end
    end,
  },
  { Pandoc = citeproc_bibliography },
}
