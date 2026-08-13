-- Counts body words against a length range, leaving out the contents, the
-- reference list and the appendices.
--
-- Captions and margin notes sit between body text and apparatus, so there are
-- two totals: body alone, and body plus those.

local MIN, MAX = 20000, 30000
local REPORT = "build/wordcount.txt"
local NAME = 40 -- width of the section column

-- Divs that are not body text.
local DROP = { references = true, appendix = true, hidden = true }

-- Level-one sections that are not body text, by class or by Quarto's id.
local DROP_SECTION = { references = true, bibliography = true, appendix = true }

-- Divs that count towards the inclusive total only.
local MARGIN = { sideblock = true, notefigure = true, ["column-margin"] = true, aside = true }

-- Not prose, so not words.
local SILENT = {
  CodeBlock = function() return {} end,
  RawBlock = function() return {} end,
  Code = function() return {} end,
  RawInline = function() return {} end,
  Math = function() return {} end,
  Cite = function() return {} end,
}

local function words(el)
  local n = 0
  for token in pandoc.utils.stringify(el:walk(SILENT)):gmatch("%S+") do
    -- A stray bracket or dash is a token but not a word.
    if token:match("%w") then n = n + 1 end
  end
  return n
end

local sections, current, dropping = pandoc.List(), nil, false

local function add(n, key)
  if dropping or n == 0 then return end
  if not current then
    current = { name = "(front matter)", body = 0, margin = 0 }
    sections:insert(current)
  end
  current[key] = current[key] + n
end

local function has(classes, set)
  for _, c in ipairs(classes) do
    if set[c] then return true end
  end
  return false
end

local function count_block(el)
  add(words(el), "body")
  return nil, false -- counted whole, so descending would count it twice
end

local function thousands(n)
  local s = tostring(n)
  local more = 1
  while more > 0 do s, more = s:gsub("^(%d+)(%d%d%d)", "%1,%2") end
  return s
end

-- Padded by hand because string.format counts bytes, not characters.
local function pad(name)
  local len = utf8.len(name) or #name
  if len > NAME then return name:sub(1, utf8.offset(name, NAME - 1) - 1) .. ".." end
  return name .. (" "):rep(NAME - len)
end

local function report()
  local body, margin = 0, 0
  for _, s in ipairs(sections) do
    body, margin = body + s.body, margin + s.margin
  end
  local total = body + margin

  local out = { "\n" }
  local function row(name, a, b)
    out[#out + 1] = ("  %s %10s %10s\n"):format(pad(name), a, b)
  end
  local function rule() out[#out + 1] = "  " .. ("-"):rep(NAME + 22) .. "\n" end
  local function note(label, value)
    out[#out + 1] = ("  %-28s%s\n"):format(label, value)
  end

  row("Section", "Body", "Margin")
  rule()
  for _, s in ipairs(sections) do
    row(s.name, thousands(s.body), thousands(s.margin))
  end
  rule()
  row("Total", thousands(body), thousands(margin))

  out[#out + 1] = "\n"
  note("Body only", thousands(body))
  note("With captions and margins", thousands(total))
  note("Target", thousands(MIN) .. "-" .. thousands(MAX))
  if body < MIN then
    note("Short of the minimum by", thousands(MIN - body) .. " words")
  elseif total > MAX then
    note("Over the maximum by", thousands(total - MAX) .. " words")
  else
    note("Within range", "yes")
  end

  -- Quarto swallows what a filter prints, so leave the report in a file.
  local f = assert(io.open(REPORT, "w"))
  f:write(table.concat(out))
  f:close()
end

local meta

local function setting(key, fallback)
  local value = meta["wordcount-" .. key]
  if not value then return fallback end
  return pandoc.utils.stringify(value)
end

return {
  -- A filter walks the metadata too, where the abstract would count as a stray
  -- paragraph. Read the settings, then put it aside until the counting is done.
  { Pandoc = function(doc)
      meta, doc.meta = doc.meta, pandoc.Meta({})
      MIN = tonumber(setting("min")) or MIN
      MAX = tonumber(setting("max")) or MAX
      REPORT = setting("report", REPORT)
      return doc
    end },

  {
    traverse = "topdown",

    Header = function(el)
      if el.level == 1 then
        -- A dropped section runs to the next level-one heading.
        dropping = has(el.classes, DROP_SECTION) or DROP_SECTION[el.identifier] or false
        if not dropping then
          current = { name = pandoc.utils.stringify(el), body = 0, margin = 0 }
          sections:insert(current)
        end
      end
      return count_block(el)
    end,

    Para = count_block,
    Plain = count_block,
    LineBlock = count_block,

    -- A table holds data, not sentences.
    Table = function() return nil, false end,

    Div = function(el)
      if el.identifier == "refs" or has(el.classes, DROP) then return nil, false end
      if has(el.classes, MARGIN) then
        add(words(el), "margin")
        return nil, false
      end
    end,

    -- The figure or table is not prose; its caption is.
    FloatRefTarget = function(el)
      if el.caption_long then add(words(el.caption_long), "margin") end
      return nil, false
    end,
  },

  -- Its own pass, so the report comes after all the counting.
  { Pandoc = function(doc)
      doc.meta = meta
      report()
      return doc
    end },
}
