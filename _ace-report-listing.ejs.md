```{=html}
<div class="ace-report-listing list">

<% items.forEach(function (item, index) { %>

  <%
    // ACE's recommendation, copied from correspondence.yml into the front
    // matter by scripts/build_report_meta.py. Same wording as Correspondence.
    const REC = {
      "retraction": "Retraction recommended",
      "expression-of-concern": "Expression of concern recommended",
      "correction": "Correction recommended"
    };
    const rec = item.recommendation && REC[item.recommendation] ? item.recommendation : "";
    const viol = item.violations || {};
  %>

  <article class="ace-report-card" data-index="<%- index %>" data-categories="<%- (item.categories || []).join(',') %>">

    <div class="ace-report-card-main">

      <div class="ace-report-card-topline">
        <div class="ace-report-card-ids">
          <% if (item["ace-id"]) { %>
            <span class="ace-report-id listing-ace-id"><%- item["ace-id"] %></span>
          <% } %>
          <% const cardDoi = item["concept-doi"] || item.doi; %>
          <% if (cardDoi) { %>
            <a class="ace-doi-link listing-doi" href="https://doi.org/<%- cardDoi %>" target="_blank" rel="noopener" title="Open the archived record, newest version (opens in a new tab)"><%- cardDoi %></a>
          <% } %>
        </div>
        <% if (rec) { %>
          <span class="ace-report-rec ace-report-rec-<%- rec %>"><%- REC[rec] %></span>
        <% } %>
      </div>

      <h2 class="ace-report-title listing-title">
        <a href="<%- item.path %>"><%- item.title %></a>
      </h2>

      <% if (item.subtitle) { %>
        <p class="ace-report-subtitle listing-subtitle"><%- item.subtitle %></p>
      <% } %>

      <%
        // Categories, tinted by facet. The four facet fields are the report's
        // own front matter; `categories` is written from them by
        // scripts/build_categories.py, so this only has to order and label.
        const FACETS = ["population", "treatment", "outcome", "design"];
        const facetOf = {};
        const ordered = [];
        const terms = item.categories || [];
        for (const f of FACETS) {
          let vals = item[f] || [];
          if (!Array.isArray(vals)) vals = [vals];
          for (const term of vals) {
            facetOf[term] = f;
            if (terms.includes(term) && !ordered.includes(term)) ordered.push(term);
          }
        }
        for (const term of terms) { if (!ordered.includes(term)) ordered.push(term); }
      %>
      <% if (ordered.length) { %>
        <div class="ace-report-categories listing-categories">
          <% for (const category of ordered) { %>
            <span class="ace-report-category"<% if (facetOf[category]) { %> data-facet="<%- facetOf[category] %>"<% } %>><%- category %></span>
          <% } %>
        </div>
      <% } %>

      <%
        // One line of numbers: violations (scripts/build_report_meta.py) and
        // citation reach (scripts/citations.py).
      %>
      <% if (viol.total || item.impact) { %>
        <div class="ace-report-stats">
          <% if (viol.total) { %>
            <span class="ace-report-stat ace-report-stat-riv"><b><%- viol.total %></b> integrity violation<%- viol.total == 1 ? "" : "s" %></span>
          <% } %>
          <% if (item.impact) { %>
            <span class="ace-report-stat ace-report-impact listing-impact" title="OpenAlex, retrieved <%- item.impact.retrieved %>">
              <span class="ace-report-impact-label">Infected</span>
              <span><b><%- item.impact.cited %></b> articles</span>
              <span><b><%- item.impact["infected-reviews"] %></b> reviews</span>
              <span><b><%- item.impact["spread-guidelines"] %></b> guidelines</span>
            </span>
          <% } %>
        </div>
      <% } %>

      <%
        // The card shows the abstract as plain text: Quarto does not run
        // citeproc over a listing, so pandoc citation syntax would appear
        // raw. Drop bracketed citations ("[-@smith2019; -@jones2020]") and
        // tidy the space they leave behind. Markdown links are left alone.
        let cardAbstract = (item.abstract || "")
          .replace(/\s*\[[^\[\]]*@[^\[\]]*\](?!\()/g, "")
          .replace(/\s+([,.;:])/g, "$1")
          .replace(/\s{2,}/g, " ")
          .trim();
      %>
      <% if (cardAbstract) { %>
        <details class="ace-listing-abstract">
          <summary>Abstract</summary>
          <div class="ace-listing-abstract-content listing-abstract">
            <%- cardAbstract %>
          </div>
        </details>
      <% } %>

      <div class="ace-report-card-foot">
        <div class="ace-report-meta ace-date-bar">
          <% if (item.date) { %>
            <div><span class="ace-date-key">Published</span><span class="ace-date-value listing-date"><%- item.date %></span></div>
          <% } %>
          <% if (item["date-modified"] && item["date-modified"] !== item.date) { %>
            <div><span class="ace-date-key">Updated</span><span class="ace-date-value listing-date-modified"><%- item["date-modified"] %></span></div>
          <% } %>
        </div>

        <div class="ace-report-card-actions">
          <a class="ace-pdf-button" href="<%- item.path %>">Read online</a>
          <% if (item["ace-id"]) { %>
            <a class="ace-pdf-button" href="reports/<%- item["ace-id"] %>/<%- item["ace-id"] %>.pdf" target="_blank">PDF</a>
          <% } %>
        </div>
      </div>

    </div>

  </article>

<% }); %>

</div>
```
