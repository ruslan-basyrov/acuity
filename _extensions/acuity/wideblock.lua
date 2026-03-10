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
    
  end
end
