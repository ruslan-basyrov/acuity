local bib, seen = {}, {}

local typst = quarto.doc.is_format("typst")

-- `sidenote-citations: false` keeps references out of the margin. 
-- A citation is printed in full by an author-date style.
local margin = true

local function read_options(meta)
  margin = meta["sidenote-citations"] ~= false
end

-- A zero-width anchor on the first citation of a work
local function mention_anchor(id)
  if typst then
    return pandoc.RawInline("typst", ('#box()#label("cite-%s")'):format(id))
  end
  return pandoc.Span({}, pandoc.Attr("cite-" .. id))
end

-- Works whose first mention is already anchored
local marked = {}

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

local function markup(inlines)
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "typst"):gsub("%s+$", "")
end

local function label_of(id)
  return ('label("%s")'):format(id:gsub('[\\"]', "\\%0"))
end

local function key_of(c)
  return label_of(c.id)
end

-- `nocite` asks for an entry in the bibliography without citing it in the text.
-- Typst lists only what it sees cited, so each key needs a citation that prints
-- nothing.
local function silent_cites(meta)
  local out = pandoc.List()
  if meta.nocite then
    meta.nocite:walk({
      Cite = function(c)
        for _, cit in ipairs(c.citations) do
          out:insert(("#cite(%s, form: none)"):format(label_of(cit.id)))
        end
      end,
    })
  end
  if #out == 0 then return nil end
  return pandoc.RawBlock("typst", table.concat(out))
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

-- Data is provenance rather than an argument, so it is cited in the text and in
-- the bibliography but kept out of the margin, which belongs to the work the
-- text engages with.
local NO_MARGIN = { dataset = true }

local function wants_margin(id)
  return not NO_MARGIN[bib[id].type]
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
  -- Plain citations are citeproc's to render; all this pass leaves is the anchor.
  if not margin then return anchor(el) end
  for _, c in ipairs(el.citations) do
    if not bib[c.id] then return nil end
  end
  local out, notes = pandoc.List(), pandoc.List()
  for _, c in ipairs(el.citations) do
    out:extend(render(c))
    if not seen[c.id] and wants_margin(c.id) then
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

-- `^[@key]` sits against the word it follows, which suits a raised marker. A
-- citation printed in full is part of the sentence and needs a space, an
-- unbreakable one so the citation is never stranded at the start of a line.
local function spaced(inlines)
  if not margin then inlines:insert(1, pandoc.Str("\u{00A0}")) end
  return inlines
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
  local out = anchor(el)
  if not margin then return out end
  for _, c in ipairs(el.citations) do
    if bib[c.id] and not seen[c.id] and wants_margin(c.id) then
      seen[c.id] = true
      out:insert(margin_ref(c))
    end
  end
  return out
end

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
      local linked = pandoc.List({ pandoc.Link(number, "#cite-" .. key) }):extend(space)
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
      pandoc.Header(1, pandoc.Str(title)),
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

-- Citeproc numbers the whole bibliography in one series. An entry outside the
-- literature carries the label it has in its own section instead, so that each
-- section counts from one. The number is the entry's first word, whether or not
-- it has been linked back to the text by then.
local function relabel(entry, label)
  local done = false
  return entry:walk({
    Str = function(str)
      if done or not str.text:match("^%d+%.?$") then return nil end
      done = true
      return pandoc.Str((str.text:gsub("^%d+", label)))
    end,
  })
end

-- Splits the bibliography, and records the label each entry moved out of it has.
local function references(div, label)
  local literature, listed = pandoc.List(), {}
  for i = 1, #CATEGORIES do listed[i] = pandoc.List() end
  for _, entry in ipairs(div.content) do
    local key = entry.t == "Div" and entry.identifier:match("^ref%-(.+)$")
    local i = key and category_of(key)
    if i then
      label[key] = CATEGORIES[i].mark .. (#listed[i] + 1)
      listed[i]:insert(relabel(entry, label[key]))
    else
      literature:insert(entry)
    end
  end
  local out = section("References", literature, div.attr)
  for i, category in ipairs(CATEGORIES) do
    if #listed[i] > 0 then
      -- The same classes as the list it came out of, so it is styled alike.
      out:extend(section(category.title, listed[i],
        pandoc.Attr("refs-" .. category.type, div.attr.classes, div.attr.attributes)))
    end
  end
  return out
end

-- A marker in the text prints citeproc's number, which the split has changed.
local function relabel_marks(blocks, label)
  return blocks:walk({
    Link = function(l)
      local key = l.target:match("^#ref%-(.+)$")
      if not (key and label[key]) then return nil end
      return pandoc.Link(pandoc.Inlines({ pandoc.Str(label[key]) }),
        l.target, l.title, l.attr)
    end,
  })
end

-- Quarto resolves a crossref only after this filter, so `@fig-1` is still a
-- citation here and citeproc would print it as a missing entry. A key the
-- bibliography does not know is a crossref, so it is set aside and put back
-- once the bibliography is built.
-- Only the body is searched: a `nocite` key names a work to list rather than
-- cite, so it is absent from the bibliography read above and would be mistaken
-- for a crossref here.
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

-- Typst backlinks an entry only from a number it prints itself, so citeproc
-- builds the bibliography here instead. In HTML the list is built here too, so
-- that both formats can split it: no filter runs late enough to see the one
-- Quarto's own citeproc would write.
local function citeproc_bibliography(doc)
  local crossrefs
  doc, crossrefs = take_crossrefs(doc)
  doc.meta.csl = doc.meta["acuity-plain-csl"]
  doc.meta["link-citations"] = true
  doc = pandoc.utils.citeproc(doc)
  -- Left in place, either key would have the template print a second bibliography.
  doc.meta.csl, doc.meta.bibliography = nil, nil
  local label = {}
  doc = doc:walk({
    -- The Typst writer cites a Cite element itself and ignores what citeproc
    -- wrote into it, so only that rendering is kept. In HTML the rendering is
    -- kept for the opposite reason: left as a citation, Quarto's own citeproc
    -- pass would render it a second time and, the bibliography now being gone,
    -- print it as missing.
    Cite = function(c)
      if typst then return c.content end
      return pandoc.Span(c.content, pandoc.Attr("", { "citation" }))
    end,
    Div = function(div)
      if div.identifier == "refs" then return references(div, label) end
      return backlinked(div)
    end,
  })
  doc.blocks = relabel_marks(doc.blocks, label)
  return put_crossrefs(doc, crossrefs)
end

if not quarto.doc.is_format("typst") then
  return {
    {
      Pandoc = function(doc)
        for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = r end
        read_options(doc.meta)
        if margin then return nil end
        -- The marker is raised and spaced in CSS, which suits a number, not a name.
        -- The entry layout is set here too: Quarto styles a bibliography it
        -- builds itself, and this one is built in the filter.
        quarto.doc.include_text("in-header", [[<style>
.citation { vertical-align: baseline; font-size: inherit; line-height: inherit; }
.column-margin .citation { margin-right: 0; }
div.csl-entry { clear: both; margin-bottom: 0.4em; }
div.csl-left-margin { min-width: 3em; float: left; }
div.csl-right-inline { margin-left: 3em; }
</style>]])
        return doc
      end,
    },
    {
      traverse = "topdown",
      Note = function(n)
        local cite = lone_cite(n)
        if cite then return spaced(expand_html(cite)), false end
        return n, false
      end,
      Cite = function(el) return expand_html(el), false end,
    },
    {
      Div = block_refs,
      FloatRefTarget = float_refs,
    },
    {
      -- Late, so that the citations the passes above rewrote are all in place.
      Pandoc = function(doc)
        if margin then return nil end
        return citeproc_bibliography(doc)
      end,
    },
  }
end

return {
  {
    Pandoc = function(doc)
      for _, r in ipairs(pandoc.utils.references(doc)) do bib[r.id] = r end
      read_options(doc.meta)
      -- Plain mode builds the bibliography further down instead, where `nocite`
      -- and the style are citeproc's business again.
      if not margin then return nil end
      -- `typst-csl` arrives from _extension.yml already resolved to a path
      -- relative to the project, which is what Typst wants. Raw, because a plain
      -- value would have its underscores escaped into an invalid path.
      local csl = doc.meta["typst-csl"]
      if csl then
        doc.meta["acuity-csl"] = pandoc.MetaInlines({
          pandoc.RawInline("typst", pandoc.utils.stringify(csl)),
        })
      end
      local cites = silent_cites(doc.meta)
      if cites then doc.blocks:insert(cites) end
      return doc
    end,
  },
  {
    traverse = "topdown",
    -- `^[@key]` means "cite this", so render it as a citation and not as a numbered note.
    Note = function(n)
      local cite = lone_cite(n)
      if cite then
        local out = expand(cite)
        if out then return spaced(out), false end
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
  {
    -- Late, so that the citations the passes above rewrote are all in place.
    Pandoc = function(doc)
      if margin then return nil end
      return citeproc_bibliography(doc)
    end,
  },
}
