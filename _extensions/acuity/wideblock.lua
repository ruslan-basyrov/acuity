function Div(el)
  if el.classes:includes("wideblock") then
    
    -- TYPST: Wrap in the marginalia #wideblock[] command
    if quarto.doc.is_format("typst") then
      local blocks = pandoc.List({ pandoc.RawBlock('typst', '#wideblock[\n') })
      blocks:extend(el.content)
      blocks:insert(pandoc.RawBlock('typst', '\n]\n'))
      return blocks

    -- HTML: Use Quarto's native grid classes
    elseif quarto.doc.is_format("html") then
      -- Add Quarto's built-in class to stretch the content into the right margin
      el.classes:insert("column-page-right")
      return el
    end
    

    elseif el.classes:includes("notefigure") then
    
    -- TYPST: Wrap in the marginalia #notefigure() command
    if quarto.doc.is_format("typst") then
      local blocks = pandoc.List({ pandoc.RawBlock('typst', '#notefigure([\n') })
      blocks:extend(el.content)
      blocks:insert(pandoc.RawBlock('typst', '\n])\n'))
      return blocks
 
    -- HTML: Use Quarto's margin column class
    elseif quarto.doc.is_format("html") then
      el.classes:insert("column-margin")
      return el
    end
    
  end
end
