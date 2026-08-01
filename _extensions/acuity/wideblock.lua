-- Runs pre-quarto (before crossref turns `{.wideblock #fig-...}` divs into
-- FloatRefTargets), so the Div still carries its classes here.
function Div(el)
  if el.classes:includes("wideblock") then

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

  elseif el.classes:includes("notefigure") then

    -- TYPST: Wrap in the marginalia #notefigure() command
    if quarto.doc.is_format("typst") then
      el.classes = el.classes:filter(function(c) return c ~= "notefigure" end)
      el = el:walk({ Cite = function(c)
        return pandoc.Span({ c }, pandoc.Attr("", { "no-footnote" }))
      end })
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

  end
end
