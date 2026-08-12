-- Runs pre-quarto (before crossref turns `{.wideblock #fig-...}` divs into
-- FloatRefTargets), so the Div still carries its classes here.

-- Keeps the caption under the figure. A wideblock covers the margin itself,
-- and a margin block is already in it, so neither can send a caption there.
-- captions.lua skips any float that already has a caption location.
local function pin_caption(el)
  el.attributes["cap-location"] = "bottom"
  el.content = el.content:walk({ Div = function(d)
    if d.identifier:match("^fig%-") or d.identifier:match("^tbl%-") then
      d.attributes["cap-location"] = "bottom"
    end
    return d
  end })
  return el
end

function Div(el)
  if el.classes:includes("wideblock") then
    el = pin_caption(el)

    -- TYPST: Wrap in marginalia's #wideblock[] command, keeping the Div
    -- (and its id) intact for crossref
    if quarto.doc.is_format("typst") then
      el.classes = el.classes:filter(function(c) return c ~= "wideblock" end)
      return pandoc.Blocks({
        pandoc.RawBlock('typst', '#wideblock['),
        el,
        pandoc.RawBlock('typst', ']'),
      })
    end
    -- HTML: handled by the .wideblock rule in custom.scss
    return el

  elseif el.classes:includes("notefigure") then
    el = pin_caption(el)

    -- TYPST: Wrap in the marginalia #notefigure() command. Keep the class, so
    -- citations.lua knows the block is in the margin and keeps the references
    -- it cites inside it.
    if quarto.doc.is_format("typst") then
      return pandoc.Blocks({
        pandoc.RawBlock('typst', '#notefigure(['),
        el,
        pandoc.RawBlock('typst', '])'),
      })

    -- HTML: Use Quarto's margin column class
    elseif quarto.doc.is_format("html") then
      el.classes:insert("column-margin")
      return el
    end

  elseif el.classes:includes("sideblock") then
    return pin_caption(el)
  end
end
