```{=html}
<%
  // Home page totals, summed across published reports. `violations` is
  // written by scripts/build_report_meta.py, `impact` by scripts/citations.py.
  const WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];
  const n = items.length;
  const t = { riv: 0, cited: 0, reviews: 0, guidelines: 0 };
  let retrieved = "";
  items.forEach(function (item) {
    const v = item.violations || {};
    const im = item.impact || {};
    t.riv += +v.total || 0;
    t.cited += +im.cited || 0;
    t.reviews += +im["infected-reviews"] || 0;
    t.guidelines += +im["spread-guidelines"] || 0;
    if (im.retrieved && im.retrieved > retrieved) retrieved = im.retrieved;
  });
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
                  "August", "September", "October", "November", "December"];
  const ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(retrieved);
  if (ymd) retrieved = MONTHS[+ymd[2] - 1] + " " + (+ymd[3]) + ", " + ymd[1];
  const heading = "What " + (n <= 10 ? WORDS[n] : n) + " audit" + (n === 1 ? "" : "s") + " found";
  const cells = [
    ["ACE-RIV", t.riv, "Research integrity violations documented"],
    ["Infected", t.cited, "Articles that cite the audited work"],
    ["Infected", t.reviews, "Systematic reviews built on it"],
    ["Spread", t.guidelines, "Clinical guidelines it reached"]
  ];
%>
<div class="ace-wrap">
  <div class="ace-home-head">
    <div><span class="ace-eyebrow">The record so far</span><h2 class="ace-home-h2"><%- heading %></h2></div>
    <p>Totals across every published report. They update with each new report and each new version.</p>
  </div>
  <div class="ace-totals">
    <% cells.forEach(function (c) { %>
      <div class="ace-total">
        <span class="ace-total-key"><%- c[0] %></span>
        <span class="ace-total-num" data-v="<%- c[1] %>"><%- c[1] %></span>
        <span class="ace-total-what"><%- c[2] %></span>
      </div>
    <% }); %>
  </div>
  <p class="ace-totals-note">Citation counts from OpenAlex<% if (retrieved) { %>, retrieved <%- retrieved %><% } %>. Integrity violations are counted under ACE-RIV.</p>
</div>
```
