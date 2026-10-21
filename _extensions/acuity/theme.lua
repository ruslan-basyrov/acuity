-- Quarto resolves fonts and colour aliases; Pandoc reads our extra settings.
local brand = require('modules/brand/brand')

return function()
  local file = assert(io.open(quarto.utils.resolve_path('_brand.yml')))
  local config = pandoc.read('---\n' .. file:read('a') .. '\n---\n', 'markdown').meta
  file:close()

  local function color(name)
    name = pandoc.utils.stringify(name)
    return (assert(brand.get_color_css('light', name), 'acuity: unknown brand colour ' .. name))
  end
  local function role(name, variable)
    local value = color(name)
    return quarto.doc.is_format('html') and ('var(' .. variable .. ', ' .. value .. ')') or value
  end

  local palette, categorical = {}, {}
  for name in pairs(config.color.palette) do palette[name] = color(name) end
  for _, name in ipairs(config.defaults.acuity.categorical) do
    table.insert(categorical, color(name))
  end

  return {
    font = brand.get_typography('light', 'base').family,
    ink = quarto.doc.is_format('html') and 'currentColor' or color('foreground'),
    muted = role('secondary', '--bs-secondary'),
    accent = role('primary', '--bs-primary'),
    paper = role('background', '--bs-body-bg'),
    palette = palette,
    categorical = categorical,
  }
end
