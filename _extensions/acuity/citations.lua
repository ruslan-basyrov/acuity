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

-- A bibliography drops the publication year of a web page and dates it by the visit
-- instead, so report whichever date the entry itself will show and never the other.
-- Returns "issued" or "accessed" and the year, or nothing when the entry has no date.
local function date_of(r)
  local visited = year(r.accessed)
  if WEB[r.type] and visited then return "accessed", visited end
  if year(r.issued) then return "issued", year(r.issued) end
  if visited then return "accessed", visited end
end

local function dated(c)
  local kind, y = date_of(bib[c.id])
  if not kind then return "" end
  -- The style owns how a publication year looks, so let it print that one.
  if kind == "issued" then return (', #cite(%s, form: "year")'):format(key_of(c)) end
  return (", accessed %s"):format(y)
end

-- Builds "[1] Author, 'Title', 2019." for the margin, or the whole entry when there is no title.
local function short_ref(c)
  local key = key_of(c)
  local title = bib[c.id].title
  if not title then return ('#cite(%s, form: "full")'):format(key) end
  -- The number is raised to match the marker in the text, and spaced like a footnote marker.
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
      -- The note has no number of its own, so the reference number is the only one.
      notes:insert(pandoc.RawInline("typst",
        ('#sidenote(numbering: none)[%s]'):format(short_ref(c))))
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

-- The same short reference the Typst side builds, as inlines bound for the margin.
local function margin_ref(c)
  local r = bib[c.id]
  if not r.title then return nil end
  -- An empty Cite of the same key is how the margin gets the number citeproc
  -- assigned, rather than a second count kept here that could drift from it.
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

-- HTML keeps citeproc's citation and trails the first one with a margin reference.
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
      Div = function(d)
        if d.classes:includes("sideblock") then return d, false end
      end,
      Cite = function(el) return expand_html(el), false end,
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
