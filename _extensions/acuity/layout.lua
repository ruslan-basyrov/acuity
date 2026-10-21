-- All unit conversion and the HTML/Typst layout differences live here.
local units = { pt = 1, px = 0.75, mm = 72 / 25.4, cm = 72 / 2.54, ['in'] = 72 }
local papers = { a4 = 595.28, a5 = 419.53, ['us-letter'] = 612, ['us-legal'] = 612 }
local stringify = pandoc.utils.stringify

local function points(value, em)
  local number, unit = stringify(value):match('^([%d.]+)(%a+)$')
  local factor = (unit == 'em' or unit == 'rem') and em or units[unit]
  assert(tonumber(number) and factor, 'acuity: expected a length such as 10pt or 2em, got ' .. stringify(value))
  return tonumber(number) * factor
end

return function(meta)
  local html = quarto.doc.is_format('html')
  local font = require('modules/brand/brand').get_typography('light', 'base')
  local layout = { em = points(font.size or meta.fontsize) }
  function layout.ems(value) return points(value, layout.em) / layout.em end
  function layout.pt(value) return string.format('%.4fpt', value * layout.em) end

  local grid = meta.grid
  local gutter = layout.ems(grid['gutter-width'])
  -- Quarto's article grid reserves 14% of the margin and adds 50px to the
  -- body before subtracting its two gutters. Keep this adaptation here.
  local margin = 0.86 * layout.ems(grid['margin-width'])
  local body = layout.ems(grid['body-width']) + layout.ems('50px') - 2 * gutter
  if not html then
    local paper = assert(papers[stringify(meta.papersize)], 'acuity: unsupported papersize')
    local edges = meta.margin
    local available = paper / layout.em - layout.ems(edges.left) - layout.ems(edges.right)
    local scale = available / (body + gutter + margin)
    body, margin, gutter = body * scale, margin * scale, gutter * scale
    meta['margin-geometry'] = {
      inner = { far = stringify(edges.left), width = '0pt', separation = '0pt' },
      outer = { far = stringify(edges.right), width = layout.pt(margin), separation = layout.pt(gutter) },
    }
  end
  assert(body > 0 and margin > 0 and gutter >= 0, 'acuity: columns must fit within the page')
  layout.columns = { body = body, margin = margin, page = body + gutter + margin }
  layout.small = layout.ems(meta.acuity.small)
  layout.figures = {
    aspectRatio = tonumber(stringify(meta.acuity.figures['aspect-ratio'])),
    minHeight = layout.ems(meta.acuity.figures['min-height']),
    legendWidth = layout.ems(meta.acuity.figures['legend-width']),
  }
  assert(layout.small > 0 and layout.figures.aspectRatio and layout.figures.aspectRatio > 0
    and layout.figures.minHeight > 0 and layout.figures.legendWidth > 0,
    'acuity: text size, figure dimensions and aspect ratio must be positive')

  if html then
    quarto.doc.add_html_dependency({ name = 'acuity', stylesheets = { 'acuity.css' } })
    quarto.doc.include_text('in-header', string.format('<style>:root { --acuity-small: %grem; }</style>', layout.small))
  else
    local file = assert(io.open(quarto.utils.resolve_path('acuity.typ')))
    quarto.doc.include_text('in-header', '#let acuity-small = ' .. layout.pt(layout.small) .. '\n' .. file:read('a'))
    file:close()
  end
  return layout
end
