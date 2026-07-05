```{=html}
<div class="ace-report-listing">

<% for (const item of items) { %>

  <article class="ace-report-card">

    <div class="ace-report-card-main">

      <div class="ace-report-card-topline">
        <% if (item["ace-id"]) { %>
          <span class="ace-report-id"><%- item["ace-id"] %></span>
        <% } %>

      </div>

      <h2 class="ace-report-title">
        <a href="<%- item.path %>"><%- item.title %></a>
      </h2>

      <% if (item.subtitle) { %>
        <p class="ace-report-subtitle"><%- item.subtitle %></p>
        <% } %>
        
      <% if (item.categories && item.categories.length) { %>
        <div class="ace-report-categories">
          <% for (const category of item.categories) { %>
            <span class="ace-report-category"><%- category %></span>
          <% } %>
        </div>
      <% } %>
        
      <% if (item.abstract) { %>
        <details class="ace-listing-abstract">
          <summary>Abstract</summary>
          <div class="ace-listing-abstract-content">
            <%- item.abstract %>
          </div>
        </details>
      <% } %>

      <div class="ace-report-meta">
        <% if (item.date) { %>
          <span><strong>Published:</strong> <%- item.date %></span>
        <% } %>

        <% if (item["date-modified"]) { %>
          <span><strong>Updated:</strong> <%- item["date-modified"] %></span>
        <% } %>
      </div>

      <div class="ace-report-card-actions">
        <a class="ace-pdf-button" href="<%- item.path %>">Read online</a>

        <% if (item.button) { %>
          <%= item.button %>
        <% } %>
      </div>

    </div>

  </article>

<% } %>

</div>
```