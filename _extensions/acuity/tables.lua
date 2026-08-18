-- Pandoc reads the width of the dashes in a markdown table as the width of the
-- column, which has nothing to do with what the column holds. Dropping the
-- widths lets the format size each column to its content.

function Table(tbl)
  local specs = tbl.colspecs
  for _, spec in ipairs(specs) do
    spec[2] = nil
  end
  tbl.colspecs = specs
  return tbl
end
