```{=html}
<%
  // Home page findings strip: every published report's `highlights:`, newest
  // report first. The list is written twice so the CSS loop is seamless; the
  // second copy is hidden from screen readers. No highlights, no strip.
  const ticks = [];
  items.forEach(function (item) {
    let hs = item.highlights || [];
    if (!Array.isArray(hs)) hs = [hs];
    hs.forEach(function (h) { if (h) ticks.push({ id: item["ace-id"], path: item.path, text: h }); });
  });
%>
<% if (ticks.length) { %>
<div class="ace-ticker" aria-label="Findings from published reports">
  <div class="ace-ticker-track">
    <% [0, 1].forEach(function (copy) { %>
      <% ticks.forEach(function (t) { %>
        <a class="ace-ui ace-tick" href="<%- t.path %>"<% if (copy) { %> aria-hidden="true" tabindex="-1"<% } %>>
          <% if (t.id) { %><span class="ace-tick-id"><%- t.id %></span><% } %>
          <span class="ace-tick-text"><%- t.text %></span>
          <span class="ace-tick-x" aria-hidden="true">✕</span>
        </a>
      <% }); %>
    <% }); %>
  </div>
</div>
<% } %>
```
