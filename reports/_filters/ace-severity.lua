-- ace-severity.lua
-- PDF typesetting for the RIV taxonomy page (riv.qmd). HTML is styled by
-- styles.css; this filter gives the same markup a LaTeX form:
--   * [Major]{.ace-sev .ace-sev-major} in a heading is lifted out of the
--     heading (so bookmarks and the TOC stay clean) and typeset as a small
--     colored label at the end of the run-in heading;
--   * ::: {.ace-riv-meta} blocks (typical evidence / counting) become an
--     indented small-print block, with [Key]{.ace-riv-key} as a grey caps key.

if not FORMAT:match("latex") then return {} end

local colors = {
  critical  = "acesevmagenta",
  major     = "acesevcyan",
  minor     = "acesevgrey",
  indicator = "acesevgrey",
}

quarto.doc.include_text("in-header", table.concat({
  "\\providecolor{acesevmagenta}{HTML}{B33FB3}",
  "\\providecolor{acesevcyan}{HTML}{0B7F97}",
  "\\providecolor{acesevgrey}{HTML}{5A6570}",
  "\\newenvironment{aceRivMeta}{\\par\\small\\begin{list}{}{\\leftmargin=1.1em\\rightmargin=0pt\\topsep=0.25\\baselineskip\\parsep=0.25\\baselineskip\\itemsep=0pt}\\item[]}{\\end{list}}",
}, "\n"))

local function tier_of(span)
  for _, c in ipairs(span.classes) do
    local t = c:match("^ace%-sev%-(%a+)$")
    if t then return t end
  end
  return "major"
end

function Header(h)
  local badge
  h.content = h.content:walk({
    Span = function(s)
      if s.classes:includes("ace-sev") then badge = s; return {} end
    end,
  })
  if not badge then return nil end
  while #h.content > 0 and h.content[#h.content].t == "Space" do
    h.content:remove(#h.content)
  end
  local color = colors[tier_of(badge)] or "acesevgrey"
  local label = pandoc.utils.stringify(badge):upper()
  local raw = pandoc.RawBlock("latex",
    "\\noindent{\\footnotesize\\bfseries\\color{"
    .. color .. "}" .. label .. "}\\par")
  return { h, raw }
end

function Div(d)
  if not d.classes:includes("ace-riv-meta") then return nil end
  local blocks = pandoc.List({ pandoc.RawBlock("latex", "\\begin{aceRivMeta}") })
  blocks:extend(d.content)
  blocks:insert(pandoc.RawBlock("latex", "\\end{aceRivMeta}"))
  return blocks
end

function Span(s)
  if not s.classes:includes("ace-riv-key") then return nil end
  local label = pandoc.utils.stringify(s):upper()
  return pandoc.RawInline("latex",
    "{\\footnotesize\\bfseries\\color{acesevgrey}" .. label .. "}\\hspace{0.5em}")
end
