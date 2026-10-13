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

-- Cover author block: a right-aligned column under an AUTHORS key and a
-- hairline. Each author gets a name, an affiliation and an email, in that
-- order, and only the lines that author actually has. The email is set in
-- mono, like the report ID and the DOIs, so it reads as an address rather
-- than as prose.
--
-- The column and the facet badges are centered together in the white space
-- between the title block and the information block. That block's top rule
-- is set in acePDF.tex: it is anchored at its bottom rule and stacks rows
-- upward, so its top edge is -10.93cm plus one 0.62cm row for each DOI the
-- report has.
--
-- Fitting more authors happens in two stages, in this order: keep the type
-- size and let the column grow upward toward the title block (SOFT_TOP to
-- HARD_TOP), then step the type down a size. A report would need seven or
-- more authors to reach the smallest step, and past that the line pitch is
-- squeezed proportionally so nothing can ever collide with the panel.
local SOFT_TOP = -1.77      -- preferred ceiling: the column sits low on the page
local HARD_TOP = 1.20       -- absolute ceiling: just clear of the dates line
local PANEL_BASE = -10.93   -- information block's top rule with no DOI rows
local PANEL_ROW = 0.62      -- one row of that block, per DOI present
local CLEARANCE = 0.85      -- white space kept at both ends of the block
                            -- (measured to a line's top, so it also covers the
                            -- depth of the last line of type)

local HEADER_DROP = 0.37    -- AUTHORS key down to its hairline
local HEADER_H    = 0.96    -- AUTHORS key down to the first name
local RULE_W      = 9.6     -- hairline length, right-aligned with the column

-- name pt, affiliation pt, email pt, name->affiliation, affiliation->email,
-- and the gap from one author's last line to the next author's name (cm).
local AUTHOR_LADDER = {
  { 13.5, 10.5, 9.5, 0.70, 0.58, 0.95 },
  { 12.0, 10.0, 9.0, 0.62, 0.52, 0.84 },
  { 11.0,  9.0, 8.0, 0.56, 0.47, 0.72 },
  { 10.0,  8.5, 7.5, 0.50, 0.43, 0.62 },
  {  9.0,  8.0, 7.0, 0.45, 0.39, 0.53 },
}

-- Where the information block's top rule sits, mirroring acePDF.tex.
local function info_panel_top(meta)
  local top = PANEL_BASE
  if stringify(meta["doi"]) ~= "" then top = top + PANEL_ROW end
  if stringify(meta["concept-doi"]) ~= "" then top = top + PANEL_ROW end
  return top
end

-- The lines each author contributes, in order.
local function author_lines(authors, meta)
  local bodies = {}
  for _, a in ipairs(authors) do
    local entry = { { kind = "name", text = latex_escape(author_name(a)) } }
    local aff = author_affiliation(a, meta)
    if aff ~= "" then table.insert(entry, { kind = "affiliation", text = latex_escape(aff) }) end
    local em = author_email(a)
    if em ~= "" then table.insert(entry, { kind = "email", text = latex_escape(em) }) end
    table.insert(bodies, entry)
  end
  return bodies
end

-- Height from the AUTHORS key to the baseline of the last line.
local function block_height(bodies, step)
  local advance = { name = step[4], affiliation = step[5], email = 0 }
  local h = HEADER_H
  for i, entry in ipairs(bodies) do
    for j = 1, #entry - 1 do h = h + advance[entry[j].kind] end
    if i < #bodies then h = h + step[6] end
  end
  return h
end

-- Returns the LaTeX for the block and the middle it was centered on, so the
-- facet badges can be centered on the same line.
local function cover_authors_block(authors, meta)
  local n = #authors
  local panel_top = info_panel_top(meta)
  if n == 0 then return "", (SOFT_TOP + panel_top) / 2 end

  local bodies = author_lines(authors, meta)
  local budgets = {
    { top = SOFT_TOP, room = (SOFT_TOP - panel_top) - 2 * CLEARANCE },
    { top = HARD_TOP, room = (HARD_TOP - panel_top) - 2 * CLEARANCE },
  }

  -- Prefer the largest type that fits; grow the column before shrinking it.
  local step, top, height
  for _, candidate in ipairs(AUTHOR_LADDER) do
    local h = block_height(bodies, candidate)
    for _, budget in ipairs(budgets) do
      if h <= budget.room then
        step, top, height = candidate, budget.top, h
        break
      end
    end
    if step then break end
  end

  local squeeze = 1.0
  if not step then
    step, top = AUTHOR_LADDER[#AUTHOR_LADDER], HARD_TOP
    height = block_height(bodies, step)
    local room = (HARD_TOP - panel_top) - 2 * CLEARANCE
    if height > room and height > 0 then
      squeeze = room / height
      height = room
    end
  end

  local name_pt, aff_pt, mail_pt = step[1], step[2], step[3]
  local advance = {
    name = step[4] * squeeze,
    affiliation = step[5] * squeeze,
    email = 0,
  }
  local gap = step[6] * squeeze

  local middle = (top + panel_top) / 2
  local y = middle + height / 2
  local out = {}

  table.insert(out, string.format(
    "\\node (aceAuthorsKey) at ([xshift=-2cm, yshift=%.2fcm]current page.east) "
    .. "[anchor=north east, inner sep=0pt, text=acecovermute] {\\aceFacetKeyFont AUTHORS};", y))
  table.insert(out, string.format(
    "\\draw[acecovermute!45, line width=0.4pt] ([xshift=-2cm, yshift=%.2fcm]current page.east) -- "
    .. "([xshift=-%.2fcm, yshift=%.2fcm]current page.east);",
    y - HEADER_DROP, 2 + RULE_W, y - HEADER_DROP))
  y = y - HEADER_H

  local style = {
    name        = string.format("\\fontsize{%.1f}{%.1f}\\selectfont\\bfseries", name_pt, name_pt * 1.2),
    affiliation = string.format("\\fontsize{%.1f}{%.1f}\\selectfont", aff_pt, aff_pt * 1.25),
    email       = string.format("\\fontsize{%.1f}{%.1f}\\selectfont\\ttfamily", mail_pt, mail_pt * 1.2),
  }

  for i, entry in ipairs(bodies) do
    for j, li in ipairs(entry) do
      local color = (li.kind == "name") and "acecoverink" or "acecovermute"
      table.insert(out, string.format(
        "\\node at ([xshift=-2cm, yshift=%.2fcm]current page.east) [anchor=north east, text=%s] {%s %s};",
        y, color, style[li.kind], li.text))
      if j < #entry then y = y - advance[li.kind] end
    end
    if i < #bodies then y = y - gap end
  end

  return table.concat(out, "\n"), middle
end

-- Author lines for the front matter page: the names on one line, and the
-- affiliations beneath them keyed by superscript. Authors sharing an
-- affiliation share its number, and when every author has the same one the
-- superscripts are dropped. Emails are left to the cover.
local function author_front_lines(authors, meta)
  local names, places, index = {}, {}, {}
  for _, a in ipairs(authors) do
    local name = latex_escape(author_name(a))
    local aff = author_affiliation(a, meta)
    local mark = ""
    if aff ~= "" then
      if index[aff] == nil then
        table.insert(places, aff)
        index[aff] = #places
      end
      mark = index[aff]
    end
    table.insert(names, { name = name, mark = mark })
  end

  local single = #places <= 1
  local line = {}
  for _, entry in ipairs(names) do
    local text = entry.name
    if not single and entry.mark ~= "" then
      text = text .. "\\textsuperscript{\\rmfamily " .. entry.mark .. "}"
    end
    table.insert(line, text)
  end

  local affs = {}
  for i, place in ipairs(places) do
    local text = latex_escape(place)
    if not single then
      text = "\\textsuperscript{\\rmfamily " .. i .. "}" .. text
    end
    table.insert(affs, text)
  end

  return table.concat(line, "\\quad "), table.concat(affs, "\\quad ")
end

-- Facet badges on the left of the cover: the same four facets, colors and
-- mono caps as the chips on the website, with the facet key set above the
-- term rather than revealed beside it on hover. Colors and fonts are
-- defined in acePDF.tex. The stack is centered in the same white space as
-- the author block (see cover_authors_block).
local FACETS = {
  { "population", "POPULATION", "acefacetpop" },
  { "treatment",  "TREATMENT",  "acefacettrt" },
  { "outcome",    "OUTCOME",    "acefacetout" },
  { "design",     "DESIGN",     "acefacetdes" },
}

local KEY_H    = 0.48   -- facet key line, to the top of the first pill
local PILL_H   = 0.56   -- pill height
local PILL_GAP = 0.11   -- between pills of the same facet
local FACET_GAP = 0.58  -- between facets

-- A metadata field that may be a list of terms or a single term.
local function meta_terms(value)
  local out = {}
  if value == nil then return out end

  -- A MetaList's entries are themselves meta values (tables with no .t);
  -- MetaInlines entries are inline elements, which do have one.
  local is_list = type(value) == "table" and type(value[1]) == "table" and value[1].t == nil
  if is_list then
    for _, item in ipairs(value) do
      local term = stringify(item)
      if term ~= "" then table.insert(out, term) end
    end
  else
    local term = stringify(value)
    if term ~= "" then table.insert(out, term) end
  end
  return out
end

local function cover_categories_block(meta, middle)
  local groups = {}
  for _, facet in ipairs(FACETS) do
    local terms = meta_terms(meta[facet[1]])
    if #terms > 0 then
      table.insert(groups, { key = facet[2], color = facet[3], terms = terms })
    end
  end
  if #groups == 0 then return "" end

  local height = 0
  for i, g in ipairs(groups) do
    height = height + KEY_H + #g.terms * PILL_H + (#g.terms - 1) * PILL_GAP
    if i < #groups then height = height + FACET_GAP end
  end

  local y = middle + height / 2
  local out = {}
  for i, g in ipairs(groups) do
    table.insert(out, string.format(
      "\\node[anchor=north west, inner sep=0pt, text=%sink] at ([xshift=2cm, yshift=%.2fcm]current page.west) {\\aceFacetKeyFont %s};",
      g.color, y, g.key))
    y = y - KEY_H
    for j, term in ipairs(g.terms) do
      table.insert(out, string.format(
        "\\node[anchor=north west, fill=%sfill, draw=%sline, line width=0.35pt, rounded corners=2.7mm, "
        .. "inner xsep=5.2pt, inner ysep=3.6pt, text=acefacettext, minimum height=%.2fcm] "
        .. "at ([xshift=2cm, yshift=%.2fcm]current page.west) {\\aceFacetTermFont \\MakeUppercase{%s}};",
        g.color, g.color, PILL_H, y, latex_escape(term)))
      y = y - PILL_H
      if j < #g.terms then y = y - PILL_GAP end
    end
    if i < #groups then y = y - FACET_GAP end
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
  table.insert(lines, "\\providecommand{\\aceAuthorsLine}{}")
  table.insert(lines, "\\providecommand{\\aceAffiliationsLine}{}")

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
    local block, middle = cover_authors_block(authors, meta)
    if block ~= "" then
      table.insert(lines, "\\renewcommand{\\coverAuthorsBlock}{" .. block .. "}")
    end

    -- Facet badges, centered on the line the author column settled on.
    local badges = cover_categories_block(meta, middle)
    if badges ~= "" then
      table.insert(lines, "\\renewcommand{\\coverCategoriesBlock}{" .. badges .. "}")
    end

    -- The same authors, set as running lines for the front matter page.
    local names_line, affs_line = author_front_lines(authors, meta)
    table.insert(lines, "\\renewcommand{\\aceAuthorsLine}{" .. names_line .. "}")
    table.insert(lines, "\\renewcommand{\\aceAffiliationsLine}{" .. affs_line .. "}")
  end

  -- PDF document properties, which Google Scholar and reference managers read
  -- from the file itself: the full title (title: subtitle) and ACE as the
  -- subject, matching the citation_* tags on the report page. pagetitle feeds
  -- the template's pdftitle; subject and keywords its pdfsubject/pdfkeywords.
  do
    local t = stringify(meta.title)
    local st = stringify(meta.subtitle)
    local id = stringify(meta["ace-id"])
    meta.pagetitle = pandoc.MetaString((st ~= "") and (t .. ": " .. st) or t)
    meta["title-meta"] = meta.pagetitle
    meta.subject = pandoc.MetaString("Audit Clinical Evidence" .. ((id ~= "") and (", report " .. id) or ""))
    meta.keywords = pandoc.MetaList({pandoc.MetaString("Audit Clinical Evidence"), pandoc.MetaString(id)})
  end

  ensure_header_includes(meta)
  table.insert(meta["header-includes"], pandoc.RawBlock("latex", table.concat(lines, "\n")))

  return meta
end