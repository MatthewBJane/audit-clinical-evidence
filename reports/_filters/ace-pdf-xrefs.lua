-- ace-pdf-xrefs.lua  (PDF only; listed AFTER `quarto` in the filter list so
-- it sees cross-references already resolved by Quarto)
--
-- Quarto renders @fig-x / @tbl-x / @sec-x in LaTeX as the prefix word plus a
-- bare \ref, so only the number is a link. This filter re-emits each as
--     \hyperref[fig-x]{Figure~\ref*{fig-x}}
-- so the whole phrase ("Figure 1", "Table 2", "Section 2.1") is the link,
-- as on the website. Colour comes from hyperref's linkcolor.

if not (quarto and quarto.doc and quarto.doc.is_format("latex")) then return {} end

local NBSP = "\u{a0}"

local XREF = { fig = true, tbl = true, sec = true, eq = true, lst = true, thm = true }

local function is_xref(label)
  local prefix = label:match("^(%a+)%-")
  return prefix ~= nil and XREF[prefix] == true
end

local function ref_label(el)
  if el.t ~= "RawInline" or el.format ~= "latex" then return nil end
  local label = el.text:match("^\\ref{([^}]+)}$")
  if label and is_xref(label) then return label end
end

local function linked(pre, word, label)
  local raw = "\\hyperref[" .. label .. "]{" .. word .. "~\\ref*{" .. label .. "}}"
  if pre ~= "" then return { pandoc.Str(pre), pandoc.RawInline("latex", raw) } end
  return { pandoc.RawInline("latex", raw) }
end

local function is_sep(el)
  return el.t == "Space" or (el.t == "Str" and el.text == NBSP)
      or (el.t == "RawInline" and el.format == "latex" and el.text == "~")
end

function Inlines(inlines)
  local out, i, changed = pandoc.List(), 1, false
  while i <= #inlines do
    local el = inlines[i]
    local label = ref_label(el)
    local done = false
    if label then
      -- prefix inside the same raw, e.g. "Figure~\ref{fig-x}"
      -- (handled below by the general raw match); here: Str word, sep, \ref
      local n = #out
      local pre, word
      if n >= 2 and is_sep(out[n]) and out[n - 1].t == "Str" then
        pre, word = out[n - 1].text:match("^(%p*)(%u%a+)$")
        if word then out:remove(n); out:remove(n - 1) end
      elseif n >= 1 and out[n].t == "Str" then
        pre, word = out[n].text:match("^(%p*)(%u%a+)" .. NBSP .. "$")
        if word then out:remove(n) end
      end
      if word then
        out:extend(linked(pre, word, label))
        done, changed = true, true
      end
    elseif el.t == "RawInline" and el.format == "latex" then
      local word, lab = el.text:match("^(%u%a+)~\\ref{([^}]+)}$")
      if word and is_xref(lab) then
        out:extend(linked("", word, lab))
        done, changed = true, true
      end
    end
    if not done then out:insert(el) end
    i = i + 1
  end
  if changed then return out end
end
