--[[
ace-tables.lua: Markdown (pandoc) tables in the PDF in the same look as the
tinytable tables: column labels in small grey mono. The rule colours (cyan
top rule, grey header and bottom rules) and type sizes are set in acePDF.tex
for both kinds of table. The PDF has no lines between body rows. LaTeX only.
]]
if not (FORMAT:match("latex") or FORMAT:match("pdf")) then return {} end

local function raw(s) return pandoc.RawInline("latex", s) end

local function style_head_cell(cell)
  local blocks = cell.contents
  if #blocks == 0 then return cell end
  local first = blocks[1]
  if first.t == "Plain" or first.t == "Para" then
    first.content:insert(1, raw("{\\aceTableHead "))
    first.content:insert(raw("}"))
  end
  return cell
end

function Table(tbl)
  for _, row in ipairs(tbl.head.rows) do
    for i, cell in ipairs(row.cells) do row.cells[i] = style_head_cell(cell) end
  end
  return tbl
end
