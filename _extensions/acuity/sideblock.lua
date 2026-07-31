function Div(el)
  if el.classes:includes("sideblock") then
    
    -- TYPST: Wrap in marginalia's #note[] command
    if quarto.doc.is_format("typst") then
      local blocks = pandoc.List({ pandoc.RawBlock('typst', '#note[\n') })
      blocks:extend(el.content)
      blocks:insert(pandoc.RawBlock('typst', '\n]\n'))
      return blocks

    -- HTML: Use Quarto's native grid classes
    elseif quarto.doc.is_format("html") then
      -- Add Quarto's built-in class to stretch the content into the right margin
      el.classes:insert("column-margin")
      return el
    end
  end
end
