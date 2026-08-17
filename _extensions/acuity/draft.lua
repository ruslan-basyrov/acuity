-- `::: draft` marks a run of unfinished text, `[...]{.draft}` an unfinished
-- phrase inside a finished one. `draft-marks: false` drops both marks and
-- leaves the text, which is the document as it would be submitted.

local marked = true

local function wrap(el, open, close, raw)
  local parts = pandoc.List({ raw("typst", open) })
  parts:extend(el.content)
  parts:insert(raw("typst", close))
  return parts
end

return {
  {
    Meta = function(meta)
      if meta["draft-marks"] ~= nil and not meta["draft-marks"] then
        marked = false
      end
    end,
  },
  {
    Div = function(el)
      if not el.classes:includes("draft") then return nil end
      if not marked then return el.content end
      if quarto.doc.is_format("typst") then
        return wrap(el, "#draftblock[", "]", pandoc.RawBlock)
      end
      return el
    end,

    Span = function(el)
      if not el.classes:includes("draft") then return nil end
      if not marked then return el.content end
      if quarto.doc.is_format("typst") then
        return wrap(el, "#draftspan[", "]", pandoc.RawInline)
      end
      return el
    end,
  },
}
