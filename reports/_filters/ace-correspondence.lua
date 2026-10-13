--[[
ace-correspondence.lua: builds the Correspondence page from correspondence.yml
(loaded into the page's metadata with `metadata-files`). Replaces the div
`::: {#ace-correspondence} :::` with:

  1. an overview board: one column per stage, each audit-journal thread as a
     chip in the column of the furthest stage it has reached;
  2. one card per audit, with a three-step tracker per journal thread, the
     recipients, and a dated log.
(See Pandoc() at the end for the placeholder ids.)

Stages: 0 letter in preparation, 1 letter sent, 2 response received (in
discussion), 3 decision (none / correction / expression of concern /
retraction). HTML only; the markup is styled by the CORRESPONDENCE block in
styles.css.
]]

local stringify = pandoc.utils.stringify

local function str(x)
  if x == nil then return "" end
  local ok, s = pcall(stringify, x)
  return ok and s or ""
end

local function list(x)
  if type(x) ~= "table" then return {} end
  if x.t == "MetaList" or #x > 0 then return x end
  return {}
end

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function slug(s)
  return (s:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", ""))
end

local STAGE_RANK = { sent = 1, response = 2, decision = 3 }
local STAGE_NAME = { [0] = "Letter in preparation", "Letter sent", "In discussion", "Decision" }
local STEP_LABEL = { "Letter sent", "Response received", "Decision" }
local OUTCOME = {
  ["none"] = { label = "No action", class = "none" },
  ["correction"] = { label = "Correction", class = "correction" },
  ["expression-of-concern"] = { label = "Expression of concern", class = "concern" },
  ["retraction"] = { label = "Retraction", class = "retraction" },
}

-- Dates are ISO strings; days between two of them, for "n days" notes.
local function to_time(d)
  local y, m, dd = d:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
end
local function days_between(a, b)
  local ta, tb = to_time(a), to_time(b)
  if not ta or not tb then return nil end
  return math.floor((tb - ta) / 86400 + 0.5)
end
local function nice_date(d)
  local t = to_time(d)
  if not t then return esc(d) end
  return os.date("%B ", t) .. tonumber(os.date("%d", t)) .. os.date(", %Y", t)
end

-- Title and subtitle of a report, read from its own front matter.
local function report_meta(id)
  local f = io.open("reports/" .. id .. "/index.qmd", "r")
  if not f then return { title = id, subtitle = "" } end
  local txt = f:read("a"); f:close()
  local fm = txt:match("^%-%-%-\n(.-)\n%-%-%-")
  if not fm then return { title = id, subtitle = "" } end
  local ok, doc = pcall(pandoc.read, "---\n" .. fm .. "\n---\n", "markdown")
  if not ok then return { title = id, subtitle = "" } end
  return { title = str(doc.meta.title), subtitle = str(doc.meta.subtitle),
           draft = doc.meta.draft == true or str(doc.meta.draft) == "true" }
end

-- Everything the page needs about one thread.
local function thread_state(th)
  local events = {}
  for _, e in ipairs(list(th.events)) do
    events[#events + 1] = { date = str(e.date), stage = str(e.stage), note = str(e.note) }
  end
  table.sort(events, function(a, b) return a.date < b.date end)
  local stage, reached = 0, {}
  for _, e in ipairs(events) do
    local r = STAGE_RANK[e.stage] or 0
    if r > 0 and not reached[r] then reached[r] = e.date end
    if r > stage then stage = r end
  end
  local outcome = OUTCOME[str(th.decision)]
  return { events = events, stage = stage, reached = reached, outcome = outcome }
end

local function status_text(st, today)
  if st.stage == 0 then
    return "The letter to the journal is being prepared."
  elseif st.stage == 1 then
    local n = days_between(st.reached[1], today)
    return "Letter sent " .. nice_date(st.reached[1]) .. "; awaiting a response" ..
      (n and n >= 0 and (" (" .. n .. (n == 1 and " day" or " days") .. ")") or "") .. "."
  elseif st.stage == 2 then
    return "Response received " .. nice_date(st.reached[2]) .. "; discussion under way."
  else
    local o = st.outcome and st.outcome.label or "Decision recorded"
    return "Decision on " .. nice_date(st.reached[3]) .. ": " .. o .. "."
  end
end

local function stepper(st)
  local h = { '<ol class="acec-steps" data-stage="' .. st.stage .. '">' }
  for i = 1, 3 do
    local state = (i < st.stage) and "done" or ((i == st.stage) and "current" or "todo")
    local extra, label = "", STEP_LABEL[i]
    if i == 3 and st.stage == 3 and st.outcome then
      extra = " acec-outcome-" .. st.outcome.class
      label = st.outcome.label
    end
    h[#h + 1] = string.format(
      '<li class="acec-step acec-%s%s"><span class="acec-dot" aria-hidden="true"></span>' ..
      '<span class="acec-step-label">%s</span><span class="acec-step-date">%s</span></li>',
      state, extra, esc(label), st.reached[i] and esc(st.reached[i]) or "&nbsp;")
  end
  h[#h + 1] = "</ol>"
  return table.concat(h)
end

local function build(meta)
  local c = meta.correspondence
  if not c then
    local none = '<p class="acec-empty">No correspondence recorded yet.</p>'
    return none, ""
  end
  local today = os.date("%Y-%m-%d")
  local updated = str(c.updated)
  -- reports marked `draft: true` are left off the page until they are published
  local audits = {}
  for _, a in ipairs(list(c.audits)) do
    if not report_meta(str(a["ace-id"])).draft then audits[#audits + 1] = a end
  end

  local board = { {}, {}, {}, {} }   -- chips per stage 0..3 (index +1)
  local cards = {}
  local n_threads, n_by_stage = 0, { [0] = 0, 0, 0, 0 }

  for _, a in ipairs(audits) do
    local id = str(a["ace-id"])
    local rm = report_meta(id)
    local rec = OUTCOME[str(a.recommendation)]
    local card = {}
    card[#card + 1] = string.format('<section class="acec-audit" id="acec-%s">', esc(id))
    card[#card + 1] = '<header class="acec-audit-head">'
    card[#card + 1] = string.format('<span class="acec-id">%s</span>', esc(id))
    card[#card + 1] = string.format('<a class="acec-title" href="reports/%s/">%s</a>', esc(id), esc(rm.title))
    if rec then
      card[#card + 1] = string.format(
        '<span class="acec-rec">ACE recommendation <span class="acec-badge acec-outcome-%s">%s</span></span>',
        rec.class, esc(rec.label))
    end
    card[#card + 1] = "</header>"
    if rm.subtitle ~= "" then
      card[#card + 1] = string.format('<p class="acec-subtitle">%s</p>', esc(rm.subtitle))
    end

    for _, th in ipairs(list(a.threads)) do
      local journal = str(th.journal)
      local publisher = str(th.publisher)
      local anchor = "acec-" .. id .. "-" .. slug(journal)
      local st = thread_state(th)
      n_threads = n_threads + 1
      n_by_stage[st.stage] = n_by_stage[st.stage] + 1

      -- board chip
      local chip_class = "acec-chip"
      if st.stage == 3 and st.outcome then chip_class = chip_class .. " acec-outcome-" .. st.outcome.class end
      table.insert(board[st.stage + 1], string.format(
        '<a class="%s" href="#%s"><span class="acec-chip-id">%s</span><span class="acec-chip-journal">%s</span>%s</a>',
        chip_class, anchor, esc(id), esc(journal),
        (st.stage == 3 and st.outcome) and ('<span class="acec-chip-outcome">' .. esc(st.outcome.label) .. '</span>') or ""))

      -- thread block
      local arts = {}
      for _, ar in ipairs(list(th.articles)) do
        local label, doi = str(ar.label), str(ar.doi)
        if doi ~= "" then
          arts[#arts + 1] = string.format('<a href="https://doi.org/%s">%s</a>', esc(doi), esc(label ~= "" and label or doi))
        else
          arts[#arts + 1] = esc(label)
        end
      end
      local t = {}
      t[#t + 1] = string.format('<div class="acec-thread acec-stage-%d%s" id="%s">', st.stage,
        (st.stage == 3 and st.outcome) and (" acec-outcome-" .. st.outcome.class) or "", anchor)
      t[#t + 1] = '<div class="acec-thread-head">'
      t[#t + 1] = string.format('<span class="acec-journal">%s</span>', esc(journal))
      if publisher ~= "" then t[#t + 1] = string.format('<span class="acec-publisher">%s</span>', esc(publisher)) end
      t[#t + 1] = string.format('<span class="acec-stage-pill acec-pill-%d">%s</span>', st.stage,
        esc(st.stage == 3 and st.outcome and st.outcome.label or STAGE_NAME[st.stage]))
      t[#t + 1] = "</div>"
      if #arts > 0 then
        t[#t + 1] = '<p class="acec-articles">' .. (#arts == 1 and "Article: " or "Articles: ") .. table.concat(arts, ", ") .. "</p>"
      end
      t[#t + 1] = stepper(st)
      t[#t + 1] = '<p class="acec-status">' .. esc(status_text(st, today)) .. "</p>"

      local recips = {}
      for _, r in ipairs(list(th.recipients)) do
        local role, org, email = str(r.role), str(r.organization), str(r.email)
        local who = esc(role)
        if org ~= "" then who = who .. ", " .. esc(org) end
        if email ~= "" then
          who = who .. string.format(' <a class="acec-email" href="mailto:%s">%s</a>', esc(email), esc(email))
        end
        recips[#recips + 1] = "<li>" .. who .. "</li>"
      end
      if #recips > 0 or #st.events > 0 then
        t[#t + 1] = '<details class="acec-log"><summary>Recipients and log' ..
          string.format(' <span class="acec-log-count">%d %s</span>', #st.events, #st.events == 1 and "entry" or "entries") ..
          "</summary>"
        if #recips > 0 then
          t[#t + 1] = '<p class="acec-log-label">Sent to</p><ul class="acec-recipients">' .. table.concat(recips) .. "</ul>"
        end
        if #st.events > 0 then
          t[#t + 1] = '<p class="acec-log-label">Log</p><ul class="acec-events">'
          for _, e in ipairs(st.events) do
            local r = STAGE_RANK[e.stage]
            t[#t + 1] = string.format(
              '<li><span class="acec-ev-date">%s</span><span class="acec-ev-stage acec-pill-%d">%s</span><span class="acec-ev-note">%s</span></li>',
              esc(e.date), r or 0, esc(r and STEP_LABEL[r] or e.stage), esc(e.note))
          end
          t[#t + 1] = "</ul>"
        end
        t[#t + 1] = "</details>"
      end
      t[#t + 1] = "</div>"
      card[#card + 1] = table.concat(t)
    end
    card[#card + 1] = "</section>"
    cards[#cards + 1] = table.concat(card, "\n")
  end

  -- overview board
  local cols = {
    { 0, "In preparation", "Letter being written" },
    { 1, "Letter sent", "Awaiting a response" },
    { 2, "In discussion", "Response received" },
    { 3, "Decision", "Journal has decided" },
  }
  local b = { '<div class="acec-board" role="list">' }
  for _, col in ipairs(cols) do
    local s = col[1]
    local chips = board[s + 1]
    b[#b + 1] = string.format(
      '<div class="acec-col acec-col-%d" role="listitem"><div class="acec-col-head">' ..
      '<span class="acec-col-num">%d</span><span class="acec-col-name">%s</span>' ..
      '<span class="acec-col-count">%d</span></div><p class="acec-col-sub">%s</p>' ..
      '<div class="acec-chips">%s</div></div>',
      s, s, esc(col[2]), #chips, esc(col[3]),
      #chips > 0 and table.concat(chips) or '<span class="acec-none">None</span>')
  end
  b[#b + 1] = "</div>"

  local summary = string.format(
    '<p class="acec-summary">%d %s across %d %s. Last updated %s.</p>',
    n_threads, n_threads == 1 and "journal thread" or "journal threads",
    #audits, #audits == 1 and "audit" or "audits", esc(nice_date(updated ~= "" and updated or today)))

  return summary .. "\n" .. table.concat(b), '<div class="acec-audits">' .. table.concat(cards, "\n") .. "</div>"
end

-- Placeholders: `#ace-correspondence-board` (summary and stage board) and
-- `#ace-correspondence-audits` (the cards), or `#ace-correspondence` for both.
function Pandoc(doc)
  if not FORMAT:match("html") then return doc end
  local board, audits = build(doc.meta)
  doc.blocks = doc.blocks:walk({
    Div = function(div)
      if div.identifier == "ace-correspondence-board" then
        return pandoc.RawBlock("html", board)
      elseif div.identifier == "ace-correspondence-audits" then
        return pandoc.RawBlock("html", audits)
      elseif div.identifier == "ace-correspondence" then
        return pandoc.RawBlock("html", board .. "\n" .. audits)
      end
    end,
  })
  return doc
end
