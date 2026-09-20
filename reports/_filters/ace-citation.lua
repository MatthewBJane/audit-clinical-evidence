-- ace-citation.lua
-- Builds the "Citation" appendix for ACE report pages from front matter, so
-- nothing has to be written twice:
--   * the cited title is `title: subtitle` (subtitle optional);
--   * authors, year, report id, DOI and URL come from the existing fields;
--   * the attribution is APA 7 (report with a number), and a BibTeX entry is
--     given alongside it.
-- Quarto's own cite-as appendix is switched off in _metadata.yml
-- (appendix-cite-as: false); this filter replaces it. HTML only.

local stringify = pandoc.utils.stringify

local SITE = "https://auditclinicalevidence.org"
local PUBLISHER = "Audit Clinical Evidence"

local function str(x) return x and stringify(x) or "" end

-- Author name parts, whether Quarto has normalised the author list
-- (by-author -> name.given/name.family) or not (given/family at top level).
local function name_parts(a)
  local n = a.name
  local given, family
  if type(n) == "table" and (n.given or n.family) then
    given, family = str(n.given), str(n.family)
  else
    given, family = str(a.given), str(a.family)
  end
  if given == "" and family == "" then
    local literal = str(a.literal ~= nil and a.literal or (n and n.literal) or a.name or a)
    -- "Given Family" -> best effort split on last space
    family = literal:match("(%S+)$") or literal
    given = literal:sub(1, #literal - #family):gsub("%s+$", "")
  end
  return given, family
end

-- "Matthew B." -> "M. B."; "Jean-Luc" -> "J.-L."
local function initials(given)
  local out = {}
  for token in given:gmatch("%S+") do
    local parts = {}
    for piece in token:gmatch("[^%-]+") do
      local first = piece:match("^%.?(.)")   -- first character (utf-8 safe enough for initials)
      -- handle multibyte first char
      local mb = piece:match("^([\194-\244][\128-\191]*)") or first
      parts[#parts + 1] = mb .. "."
    end
    out[#out + 1] = table.concat(parts, "-")
  end
  return table.concat(out, " ")
end

local function apa_authors(list)
  local names = {}
  for _, a in ipairs(list) do
    local given, family = name_parts(a)
    local ini = initials(given)
    names[#names + 1] = ini ~= "" and (family .. ", " .. ini) or family
  end
  local n = #names
  if n == 0 then return "" end
  if n == 1 then return names[1] end
  if n == 2 then return names[1] .. ", & " .. names[2] end
  if n <= 20 then
    return table.concat(names, ", ", 1, n - 1) .. ", & " .. names[n]
  end
  -- APA 7: first 19, ellipsis, last
  return table.concat(names, ", ", 1, 19) .. ", ... " .. names[n]
end

local function bibtex_authors(list)
  local names = {}
  for _, a in ipairs(list) do
    local given, family = name_parts(a)
    names[#names + 1] = given ~= "" and (family .. ", " .. given) or family
  end
  return table.concat(names, " and ")
end

local function bib_escape(s)
  return (s:gsub("([&%%#_])", "\\%1"))
end

function Pandoc(doc)
  if quarto and quarto.doc and not quarto.doc.is_format("html") then return nil end
  local meta = doc.meta

  local title = str(meta.title)
  local subtitle = str(meta.subtitle)
  local full_title = subtitle ~= "" and (title .. ": " .. subtitle) or title

  local ace_id = str(meta["ace-id"])
  local date = str(meta.date)
  local year, month = date:match("^(%d%d%d%d)%-(%d%d)")
  year = year or date:match("(%d%d%d%d)") or ""

  local authors = meta["by-author"] or meta.author or {}
  if authors.t == "MetaMap" or (type(authors) == "table" and authors.name) then authors = { authors } end

  local doi = str(meta.doi)
  local concept = str(meta["concept-doi"])
  -- Expose both DOIs to the page scripts. The ID pill links the CONCEPT DOI,
  -- which always resolves to the newest version; the version DOI pins this
  -- revision and belongs in the citation and the version history.
  if doi ~= "" and quarto and quarto.doc then
    quarto.doc.include_text("in-header", '<meta name="ace-doi" content="' .. doi .. '">')
  end
  if concept ~= "" and quarto and quarto.doc then
    quarto.doc.include_text("in-header", '<meta name="ace-concept-doi" content="' .. concept .. '">')
  end
  local url = SITE .. "/reports/" .. ace_id .. "/"
  local locator = doi ~= "" and ("https://doi.org/" .. doi) or url

  -- APA 7, report with a report number:
  -- Author, A. A., & Author, B. B. (Year). Title: Subtitle (Report No. X). Publisher. https://doi.org/...
  local apa = pandoc.Para({
    pandoc.Str(apa_authors(authors) .. " (" .. year .. "). "),
    pandoc.Emph({ pandoc.Str(full_title) }),
    pandoc.Str(" (Report No. " .. ace_id .. "). " .. PUBLISHER .. ". "),
    pandoc.Link({ pandoc.Str(locator) }, locator),
  })

  local bib = {
    "@techreport{" .. ace_id .. ",",
    "  author      = {" .. bib_escape(bibtex_authors(authors)) .. "},",
    "  title       = {" .. bib_escape(full_title) .. "},",
    "  institution = {" .. PUBLISHER .. "},",
    "  type        = {ACE audit report},",
    "  number      = {" .. ace_id .. "},",
    "  year        = {" .. year .. "},",
  }
  if month then bib[#bib + 1] = "  month       = {" .. tonumber(month) .. "}," end
  if doi ~= "" then bib[#bib + 1] = "  doi         = {" .. doi .. "}," end
  bib[#bib + 1] = "  url         = {" .. url .. "}"
  bib[#bib + 1] = "}"

  local blocks = {
    pandoc.Header(2, { pandoc.Str("Citation") }, pandoc.Attr("citation", { "appendix" })),
    pandoc.Para({ pandoc.Str("APA:") }),
    pandoc.Div({ apa }, pandoc.Attr("", { "ace-cite-apa" })),
    pandoc.Para({ pandoc.Str("BibTeX:") }),
    pandoc.CodeBlock(table.concat(bib, "\n"), pandoc.Attr("", { "bibtex" })),
  }
  if concept ~= "" then
    blocks[#blocks + 1] = pandoc.Para({
      pandoc.Str("This citation points to this version. To refer to the report in general, use the concept DOI, which always resolves to the latest version: "),
      pandoc.Link({ pandoc.Str("https://doi.org/" .. concept) }, "https://doi.org/" .. concept),
    })
  end

  for _, b in ipairs(blocks) do doc.blocks:insert(b) end
  return doc
end
