-- Places Acuity's blocks. Runs before Quarto turns `{.wideblock #fig-...}`
-- divs into floats, so a div still carries its classes here.

local typst = quarto.doc.is_format("typst")

-- `draft-marks: false` drops the draft marks and leaves the text, which is the
-- document as it would be submitted.
local marked = true

-- The Typst call around each block, and the HTML class it takes. Quarto
-- rebuilds a float and drops its classes, so a wideblock's class moves to a
-- wrapper div instead.
local BLOCKS = {
  { class = "wideblock", typst = { "#wideblock[", "]" }, html = "wideblock", wrap = true },
  { class = "notefigure", typst = { "#notefigure([", "])" }, html = "column-margin" },
  -- Full width, or a figure in it would not centre in the note.
  { class = "sideblock", typst = { "#note(numbering: none)[", "]" }, html = "column-margin", full = true },
}

-- Keeps the caption under the figure. A wideblock covers the margin itself,
-- and a margin block is already in it, so neither can send a caption there.
-- captions.lua skips any float that already has a caption location.
local function pin_caption(el)
  el.attributes["cap-location"] = "bottom"
  el.content = el.content:walk({
    Div = function(d)
      if d.identifier:match("^fig%-") or d.identifier:match("^tbl%-") then
        d.attributes["cap-location"] = "bottom"
      end
      return d
    end,
    -- A labelled markdown table is a Table, not a Div, and this early its
    -- label still sits in the caption text, so every table is pinned. The
    -- caption stays where tables put it: on top.
    Table = function(t)
      t.attributes["cap-location"] = "top"
      return t
    end,
  })
end

-- The div stays inside the Typst call, so that citations.lua still sees which
-- block a citation is in.
local function place(el, block)
  pin_caption(el)
  if block.wrap then
    el.classes = el.classes:filter(function(c) return c ~= block.class end)
  end
  if typst then
    if block.full then el.attributes["typst:width"] = "100%" end
    return pandoc.Blocks({
      pandoc.RawBlock("typst", block.typst[1]),
      el,
      pandoc.RawBlock("typst", block.typst[2]),
    })
  end
  if block.wrap then return pandoc.Div(el, pandoc.Attr("", { block.html })) end
  el.classes:insert(block.html)
  return el
end

-- `::: draft` marks a run of unfinished text, `[...]{.draft}` an unfinished
-- phrase inside a finished one.
local function draft(el, open, raw)
  if not el.classes:includes("draft") then return nil end
  if not marked then return el.content end
  if not typst then return nil end
  local out = pandoc.List({ raw("typst", open) })
  out:extend(el.content)
  out:insert(raw("typst", "]"))
  return out
end

return {
  {
    Meta = function(meta) marked = meta["draft-marks"] ~= false end,
  },
  {
    Div = function(el)
      for _, block in ipairs(BLOCKS) do
        if el.classes:includes(block.class) then return place(el, block) end
      end
      return draft(el, "#draftblock[", pandoc.RawBlock)
    end,
    Span = function(el) return draft(el, "#draftspan[", pandoc.RawInline) end,
    -- Pandoc reads the width of the dashes in a markdown table as the width of
    -- the column, which has nothing to do with what the column holds. Dropping
    -- the widths lets the format size each column to its content.
    Table = function(tbl)
      local specs = tbl.colspecs
      for _, spec in ipairs(specs) do spec[2] = nil end
      tbl.colspecs = specs
      return tbl
    end,
  },
}
