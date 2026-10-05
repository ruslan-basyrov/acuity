-- Places Acuity's blocks. A wideblock spans the text and the margin, a
-- notefigure or a sideblock sits in the margin, and any other float stays in
-- the text with its caption in the margin, level with the top of the float.

local typst = quarto.doc.is_format("typst")

-- `draft-marks: false` drops the draft marks and leaves the text, which is the
-- document as it would be submitted.
local marked = true

-- The Typst call around each block. The element stays inside it, so that
-- citations.lua still sees which block a citation is in.
local BLOCKS = {
  wideblock = { "#wideblock[", "]" },
  notefigure = { "#notefigure([", "])" },
  -- Full width, or a figure in it would not centre in the note.
  sideblock = { "#note(numbering: none)[#block(width: 100%)[", "]]" },
}

local function typst_call(node, call)
  return pandoc.Blocks({ pandoc.RawBlock("typst", call[1]), node, pandoc.RawBlock("typst", call[2]) })
end

-- In HTML a block in the margin takes Quarto's class for it. Quarto drops the
-- classes of a float it lays out as a panel, so a wideblock's class moves to a
-- wrapper div.
local function place(el, node)
  local class = el.classes:find_if(function(c) return BLOCKS[c] end)
  if not class then return nil end
  if typst then return typst_call(node, BLOCKS[class]) end
  if class == "wideblock" then
    el.classes = el.classes:filter(function(c) return c ~= class end)
    return pandoc.Div(node, pandoc.Attr("", { class }))
  end
  el.classes:insert("column-margin")
  return el
end

-- Quarto's own margin captions leave a panel layout with a caption position
-- Typst cannot read, so in Typst the caption goes on top and the template's
-- `margincaption` turns it into a note.
local function margin_caption(float, node)
  -- A caption the author placed, or one already in the margin, stays.
  if float.attributes["cap-location"] or float.classes:includes("column-margin") then
    return nil
  end
  if not typst then
    float.attributes["cap-location"] = "margin"
    return float
  end
  float.attributes["cap-location"] = "top"
  return typst_call(node, { "#margincaption[", "]" })
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
  -- Top down, so that the walk stops at a block in the margin or across it:
  -- the floats in it keep their captions underneath.
  {
    traverse = "topdown",
    Div = function(div)
      if div.classes:includes("column-margin") then return nil, false end
      local placed = place(div, div)
      if placed then return placed, false end
    end,
    FloatRefTarget = function(float, node)
      return place(float, node) or margin_caption(float, node), false
    end,
  },
  {
    Div = function(el) return draft(el, "#draftblock[", pandoc.RawBlock) end,
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
