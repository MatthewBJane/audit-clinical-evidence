-- fields.lua
-- Converts Quarto/Pandoc metadata into LaTeX macros for the ACE PDF cover.

local function stringify(x)
  if x == nil then return "" end
  return pandoc.utils.stringify(x)
end

local function latex_escape(s)
  if s == nil then return "" end
  s = tostring(s)

  s = s:gsub("\\", "\\textbackslash{}")
  s = s:gsub("([%%$#&_{}])", "\\%1")
  s = s:gsub("~", "\\textasciitilde{}")
  s = s:gsub("%^", "\\textasciicircum{}")

  return s
end

local function provide(name, value)
  return "\\providecommand{\\" .. name .. "}{" .. latex_escape(value) .. "}"
end

local function renew(name, value)
  return "\\renewcommand{\\" .. name .. "}{" .. latex_escape(value) .. "}"
end

local function get(obj, key)
  if obj == nil then return nil end
  return obj[key]
end

local function format_place(city, state, country)
  local place = {}

  if city ~= "" then table.insert(place, city) end
  if state ~= "" then table.insert(place, state) end
  if country ~= "" then table.insert(place, country) end

  return table.concat(place, ", ")
end

local function format_affiliation(aff)
  if aff == nil then return "" end

  local name = stringify(get(aff, "name"))
  local department = stringify(get(aff, "department"))
  local city = stringify(get(aff, "city"))

  -- Quarto may use region instead of state.
  local state = stringify(get(aff, "state"))
  if state == "" then
    state = stringify(get(aff, "region"))
  end

  local country = stringify(get(aff, "country"))

  -- If it is just a string, use it directly.
  if name == "" and department == "" and city == "" and state == "" and country == "" then
    return stringify(aff)
  end

  local parts = {}

  if department ~= "" then table.insert(parts, department) end
  if name ~= "" then table.insert(parts, name) end

  local place = format_place(city, state, country)
  if place ~= "" then table.insert(parts, place) end

  return table.concat(parts, ", ")
end

local function find_global_affiliation(meta, id)
  if id == nil or id == "" then return "" end

  local affs = get(meta, "affiliations")
  if affs == nil then return "" end

  for _, aff in ipairs(affs) do
    local aff_id = stringify(get(aff, "id"))
    if aff_id == id then
      return format_affiliation(aff)
    end
  end

  return ""
end

local function author_name(author)
  if author == nil then return "" end

  local name = get(author, "name")

  -- Quarto by-author often stores name.literal.
  if name ~= nil then
    local literal = stringify(get(name, "literal"))
    local given = stringify(get(name, "given"))
    local family = stringify(get(name, "family"))

    if literal ~= "" then
      return literal
    elseif given ~= "" and family ~= "" then
      return given .. " " .. family
    end
  end

  local literal = stringify(get(author, "literal"))
  local given = stringify(get(author, "given"))
  local family = stringify(get(author, "family"))
  local simple_name = stringify(get(author, "name"))

  if literal ~= "" then
    return literal
  elseif simple_name ~= "" then
    return simple_name
  elseif given ~= "" and family ~= "" then
    return given .. " " .. family
  else
    return stringify(author)
  end
end

local function author_email(author)
  if author == nil then return "" end

  local email = stringify(get(author, "email"))
  if email ~= "" then return email end

  local emails = get(author, "emails")
  if emails ~= nil and emails[1] ~= nil then
    return stringify(emails[1])
  end

  return ""
end

local function author_affiliation(author, meta)
  if author == nil then return "" end

  -- Direct single affiliation.
  local aff = get(author, "affiliation")
  if aff ~= nil then
    local out = format_affiliation(aff)
    if out ~= "" then return out end
  end

  -- Direct affiliation list.
  local affs = get(author, "affiliations")
  if affs ~= nil and affs[1] ~= nil then
    local first = affs[1]

    -- Sometimes Quarto stores only an affiliation id/ref.
    local ref = stringify(get(first, "ref"))
    if ref == "" then ref = stringify(get(first, "id")) end
    if ref == "" then ref = stringify(first) end

    local resolved = find_global_affiliation(meta, ref)
    if resolved ~= "" then return resolved end

    local out = format_affiliation(first)
    if out ~= "" then return out end
  end

  -- Other possible id fields.
  local aff_id = stringify(get(author, "affiliation-id"))
  if aff_id == "" then aff_id = stringify(get(author, "affiliation_id")) end
  if aff_id == "" then aff_id = stringify(get(author, "affiliation")) end

  local resolved = find_global_affiliation(meta, aff_id)
  if resolved ~= "" then return resolved end

  return ""
end

local function ensure_header_includes(meta)
  if meta["header-includes"] == nil then
    meta["header-includes"] = pandoc.List()
  elseif meta["header-includes"].t ~= nil then
    meta["header-includes"] = pandoc.List({ meta["header-includes"] })
  end
end

-- Cover author block: emits one tikz node per line (name, affiliation,
-- email) for every author, stacked from the top of the author area
-- downwards. Type size and line pitch shrink as the author count grows so
-- the block stays above the bottom-left information lines (which begin at
-- -11cm). With three lines per author: 1-2 authors at \Large, 3 at
-- \normalsize, 4 at \small (ends ~-11.1cm), 5 at \footnotesize
-- (~-11.7cm). Six or more would need a two-column redesign.
local function cover_authors_block(authors, meta)
  local n = #authors
  if n == 0 then return "" end

  local size, pitch, gap
  if n <= 2 then     size, pitch, gap = "\\Large",        0.70, 0.40
  elseif n == 3 then size, pitch, gap = "\\normalsize",   0.50, 0.30
  elseif n == 4 then size, pitch, gap = "\\small",        0.45, 0.25
  else               size, pitch, gap = "\\footnotesize", 0.40, 0.20
  end

  local y = -4.7
  local out = {}
  local function node(body)
    table.insert(out, string.format(
      "\\node at (current page.east) [anchor=east, yshift=%.2fcm, xshift=-2cm] {%s %s};",
      y, size, body))
    y = y - pitch
  end

  for _, a in ipairs(authors) do
    node("\\textbf{" .. latex_escape(author_name(a)) .. "}")
    local aff = author_affiliation(a, meta)
    if aff ~= "" then node(latex_escape(aff)) end
    local em = author_email(a)
    if em ~= "" then node(latex_escape(em)) end
    y = y - gap
  end

  return table.concat(out, "\n")
end

function Meta(meta)
  local lines = {}

  -- Defaults.
  table.insert(lines, provide("aceID", ""))
  table.insert(lines, provide("outputFile", ""))
  table.insert(lines, provide("dateModified", ""))
  table.insert(lines, provide("aceDOI", ""))
  table.insert(lines, provide("aceConceptDOI", ""))
  table.insert(lines, provide("reportStatus", ""))
  table.insert(lines, provide("reportJournal", ""))

  table.insert(lines, provide("coverAuthorOne", ""))
  table.insert(lines, provide("coverAffiliationOne", ""))
  table.insert(lines, provide("coverEmailOne", ""))

  table.insert(lines, provide("coverAuthorTwo", ""))
  table.insert(lines, provide("coverAffiliationTwo", ""))
  table.insert(lines, provide("coverEmailTwo", ""))

  table.insert(lines, "\\providecommand{\\coverAuthorsBlock}{}")

  -- Report fields.
  table.insert(lines, renew("aceID", stringify(meta["ace-id"])))
  table.insert(lines, renew("outputFile", stringify(meta["output-file"])))
  table.insert(lines, renew("dateModified", stringify(meta["date-modified"])))
  table.insert(lines, renew("aceDOI", stringify(meta["doi"])))
  table.insert(lines, renew("aceConceptDOI", stringify(meta["concept-doi"])))
  table.insert(lines, renew("reportStatus", stringify(meta["Status"] or meta["status"])))
  table.insert(lines, renew("reportJournal", stringify(meta["Journal"] or meta["journal"])))

  -- Prefer Quarto's richer author metadata.
  local authors = meta["by-author"]

  -- Fallback to Pandoc author metadata.
  if authors == nil then
    authors = meta["author"]
  end

  if authors ~= nil then
    local a1 = authors[1]
    local a2 = authors[2]

    if a1 ~= nil then
      table.insert(lines, renew("coverAuthorOne", author_name(a1)))
      table.insert(lines, renew("coverAffiliationOne", author_affiliation(a1, meta)))
      table.insert(lines, renew("coverEmailOne", author_email(a1)))
    end

    if a2 ~= nil then
      table.insert(lines, renew("coverAuthorTwo", author_name(a2)))
      table.insert(lines, renew("coverAffiliationTwo", author_affiliation(a2, meta)))
      table.insert(lines, renew("coverEmailTwo", author_email(a2)))
    end

    -- Any number of authors (see cover_authors_block). Not passed through
    -- latex_escape: the block is LaTeX, its text parts are escaped inside.
    local block = cover_authors_block(authors, meta)
    table.insert(lines, "\\renewcommand{\\coverAuthorsBlock}{" .. block .. "}")
  end

  ensure_header_includes(meta)
  table.insert(meta["header-includes"], pandoc.RawBlock("latex", table.concat(lines, "\n")))

  return meta
end