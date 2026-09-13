-- ace-riv-links.lua
-- RIV references in report text.
--
--   @riv-1.7        ->  **Peer Review Subversion (RIV 1.7)**   (name from riv.yml)
--   3-@riv-1.7      ->  the same label; the "3-" is a DECLARATION that the
--                       report records three instances of RIV 1.7. It is
--                       stripped from the output. riv_summary_table() and
--                       scripts/riv_check.py read these declarations (and only
--                       these) to build the summary table, so the prose around
--                       them is free, and a later plain @riv-1.7 is just a link.
--   [-@riv-1.7]     ->  **RIV 1.7**                              (compact form)
--   [@riv-1.3; @riv-1.7]  -> both, comma-separated
--
-- The whole label is a link to the taxonomy entry (riv.html#riv-1-7), opened
-- in a new tab in HTML; the PDF gets the same bold text as a hyperlink.
-- Hand-written **Name (RIV 1.7)** and **RIV 1.7** labels (e.g. in tables)
-- are linked the same way in HTML.
--
-- Names come from riv.yml at the project root, so a report can never spell a
-- category differently from the taxonomy; an unknown number stops the render.
-- Runs before citeproc (Quarto applies user filters first), so the @riv-
-- keys never reach the bibliography.

local RIV_URL = "https://auditclinicalevidence.org/riv.html"

-- ---- taxonomy ------------------------------------------------------------
local function find_taxonomy()
  local candidates = {}
  if quarto and quarto.project and quarto.project.directory then
    table.insert(candidates, quarto.project.directory .. "/riv.yml")
  end
  for _, p in ipairs({ "riv.yml", "../riv.yml", "../../riv.yml", "../../../riv.yml" }) do
    table.insert(candidates, p)
  end
  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then return f, p end
  end
  return nil
end

local function load_names()
  local f, path = find_taxonomy()
  if not f then
    error("ace-riv.lua: riv.yml not found (looked relative to the project root and the document)")
  end
  local names, current = {}, nil
  for line in f:lines() do
    local num = line:match('^%s*%-%s*number:%s*"?([%d%.]+)"?%s*$')
    if num then current = num end
    local name = line:match("^%s*name:%s*(.-)%s*$")
    if name and current then
      name = name:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      names[current] = name
      current = nil
    end
  end
  f:close()
  return names
end

local NAMES = nil
local function name_of(num)
  NAMES = NAMES or load_names()
  local n = NAMES[num]
  if not n then error("ace-riv.lua: @riv-" .. num .. " is not a category in riv.yml") end
  return n
end

-- ---- link construction ---------------------------------------------------
local function riv_link(num, inlines)
  local anchor = RIV_URL .. "#riv-" .. (num:gsub("%.", "-"))
  local attr = pandoc.Attr("", { "ace-riv-link" }, { target = "_blank", rel = "noopener" })
  return pandoc.Link(inlines, anchor, "ACE-RIV " .. num, attr)
end

-- PDF: hyperref colours \href in the template's light grey (urlcolor), so
-- the label is wrapped in its own colour (steel blue, as on the site).
local LATEX = quarto and quarto.doc and quarto.doc.is_format("latex")
if LATEX then
  quarto.doc.include_text("in-header", "\\providecolor{acerivblue}{HTML}{2F6F8F}")
end

local function label(num, compact)
  local text = compact and ("RIV " .. num) or (name_of(num) .. " (RIV " .. num .. ")")
  if LATEX then
    local url = RIV_URL .. "#riv-" .. (num:gsub("%.", "-"))
    return {
      pandoc.RawInline("latex", "\\href{" .. url .. "}{\\textcolor{acerivblue}{\\textbf{"),
      pandoc.Str(text),
      pandoc.RawInline("latex", "}}}"),
    }
  end
  return pandoc.Strong({ riv_link(num, { pandoc.Str(text) }) })
end

-- ---- declarations: drop the "N-" in front of a RIV reference -------------
local function is_riv_cite(el)
  if el.t ~= "Cite" then return false end
  for _, c in ipairs(el.citations) do
    if c.id:match("^riv%-%d+%.%d+$") then return true end
  end
  return false
end

local function strip_declarations(inlines)
  local changed = false
  for i = 1, #inlines - 1 do
    local el = inlines[i]
    if el.t == "Str" and is_riv_cite(inlines[i + 1]) then
      local pre = el.text:match("^(.-)%d+%-$")
      if pre then
        inlines[i] = pandoc.Str(pre)
        changed = true
      end
    end
  end
  if changed then
    local out = pandoc.List()
    for _, el in ipairs(inlines) do
      if not (el.t == "Str" and el.text == "") then out:insert(el) end
    end
    return out
  end
end

-- ---- @riv-x.y citations --------------------------------------------------
function Cite(el)
  local out, any = {}, false
  for i, c in ipairs(el.citations) do
    local num = c.id:match("^riv%-(%d+%.%d+)$")
    if num then
      any = true
      if i > 1 then table.insert(out, pandoc.Str(", ")) end
      local lab = label(num, c.mode == "SuppressAuthor")
      if lab.t then table.insert(out, lab) else for _, x in ipairs(lab) do table.insert(out, x) end end
    end
  end
  if not any then return nil end
  -- mixed brackets ([@riv-1.7; @smith2020]) are not supported: keep RIV refs only
  return out
end

-- ---- hand-written bold labels (HTML only; PDF keeps plain bold) ----------
function Strong(el)
  if not (quarto and quarto.doc and quarto.doc.is_format("html")) then return nil end
  -- already linked by Cite above
  if #el.content == 1 and el.content[1].t == "Link" then return nil end
  local s = pandoc.utils.stringify(el)
  local num = s:match("%(RIV (%d+%.%d+)%)$") or s:match("^RIV (%d+%.%d+)$")
  if not num then return nil end
  return pandoc.Strong({ riv_link(num, el.content) })
end

-- Two passes: strip the declaration counts, then convert the references.
return {
  { Inlines = strip_declarations },
  { Cite = Cite, Strong = Strong },
}
