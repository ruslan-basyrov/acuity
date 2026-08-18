-- Moves the caption of a body-column figure into the margin, aligned with the
-- top of the figure.
--
-- The document-level setting cannot be used: Quarto lets it override the
-- caption location of a single float, and a wideblock or a figure already in
-- the margin has to keep its caption underneath. wideblock.lua sets a caption
-- location on those, so a float without one is a body float.
local typst = quarto.doc.is_format("typst")

-- In Typst the caption is moved here rather than by Quarto, whose margin
-- captions leave a panel layout with a caption position Typst cannot read.
-- This uses marginalia: a top caption becomes a note, and notes are shifted to
-- keep clear of each other.
local function to_margin(float_node)
  return pandoc.Blocks({
    pandoc.RawBlock("typst", "#[\n#set figure(gap: 0pt)\n" ..
      "#show figure.caption: it => sidenote(alignment: \"top\", dy: -0.01pt, " ..
      "counter: none, shift: \"avoid\", keep-order: true)[#it]\n" ..
      "#show figure.caption: set text(size: 8pt, fill: brand-color.foreground)\n"),
    float_node,
    pandoc.RawBlock("typst", "]\n"),
  })
end

return {
  FloatRefTarget = function(float, float_node)
    if float.parent_id then return nil end
    if float.classes:includes("column-margin") or float.classes:includes("notefigure") then
      return nil
    end
    if float.attributes["cap-location"] then return nil end
    if not typst then
      float.attributes["cap-location"] = "margin"
      return float
    end
    float.attributes["cap-location"] = "top"
    return to_margin(float_node)
  end,
}
