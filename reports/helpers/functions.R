grimmer_tt <- function(data,
                       mean_col,
                       sd_col,
                       n_col,
                       id_cols = NULL,
                       items = 1,
                       notes = NULL,
                       table = TRUE,
                       yes_color = ace_blue_dark,
                       no_color = ace_purple_dark) {
  
  mean_col <- rlang::ensym(mean_col)
  sd_col   <- rlang::ensym(sd_col)
  n_col    <- rlang::ensym(n_col)
  
  grimmer_results <- data |>
    scrutiny::grimmer_map(
      x = !!mean_col,
      sd = !!sd_col,
      n = !!n_col,
      items = items
    ) |>
    dplyr::transmute(
      Consistent = dplyr::if_else(consistency, "Yes", "No"),
      Reason = reason
    )
  
  out <- data |>
    dplyr::bind_cols(grimmer_results)
  
  if (!is.null(id_cols)) {
    out <- out |>
      dplyr::select(
        dplyr::any_of(id_cols),
        Mean = !!mean_col,
        SD = !!sd_col,
        n = !!n_col,
        Consistent,
        Reason
      )
  } else {
    out <- out |>
      dplyr::select(
        Mean = !!mean_col,
        SD = !!sd_col,
        n = !!n_col,
        Consistent,
        Reason
      )
  }
  
  if (!table) {
    return(out)
  }
  
  consistent_col <- which(names(out) == "Consistent")
  center_cols <- which(names(out) %in% c("Mean", "SD", "n", "Consistent"))
  
  # House style: a note beginning "Note." / "Note:" gets an italic "Note." label.
  if (!is.null(notes) && is.character(notes)) {
    notes <- sub("^\\s*Note[.:]\\s*",
                 if (knitr::is_html_output()) "<i>Note.</i> " else "\\textit{Note.} ",
                 notes)
  }
  tab <- tinytable::tt(out, notes = notes, class = "ace-grimmer-table") |>
    tinytable::style_tt(
      j = 1:ncol(out),
      valign = "m"
    ) |>
    tinytable::style_tt(
      j = center_cols,
      align = "c"
    )
  
  if (knitr::is_html_output()) {
    
    tab <- tab |>
      tinytable::style_tt(
        i = which(out$Consistent == "Yes"),
        j = consistent_col,
        background = yes_color,
        color = "white",
        bold = TRUE
      ) |>
      tinytable::style_tt(
        i = which(out$Consistent == "No"),
        j = consistent_col,
        background = no_color,
        color = "white",
        bold = TRUE
      )
    
  } else {
    
    tab <- tab |>
      tinytable::style_tt(
        i = which(out$Consistent == "Yes"),
        j = consistent_col,
        background = yes_color,
        color = "white",
        bold = TRUE,
        line = "tblr",
        line_color = "white",
        line_width = 0.2
      ) |>
      tinytable::style_tt(
        i = which(out$Consistent == "No"),
        j = consistent_col,
        background = no_color,
        color = "white",
        bold = TRUE,
        line = "tblr",
        line_color = "white",
        line_width = 0.2
      )
  }
  
  tab
}

# ---------------------------------------------------------------------------
# citation_table(): Table of citation counts for the audited papers, from the
# CSV written by scripts/citations.py (OpenAlex). Emits a markdown pipe table
# so that citation keys in `labels` become live citations; use in a chunk with
# `#| results: asis`. Rendering never touches the network: the numbers are
# whatever was retrieved when the script last ran (date recorded in the CSV).
#
#   citation_table("reports/ACE2026001/data/citations.csv",
#                  labels = c("10.1097/MD.0000000000015344" = "@abdelbasset2019a"),
#                  caption = "Citation counts for audited studies", label = "tbl-impact")
#
# Columns (short heads; each is defined precisely in the note under the table):
#   Infected articles        works indexed by OpenAlex that cite the paper
#   Infected reviews         citing works OpenAlex types as "review", or whose
#                            title indicates a meta-analysis or review
#   Spread via reviews       citations received by the infected reviews in that
#                            row (shown if `downstream = TRUE`)
#   Spread to guidelines     distinct guideline-like works that cite the paper
#                            directly or cite one of its infected reviews
#                            (journal-published only; the indirect part needs a
#                            CSV from `citations.py --deep`; shown if `guidelines = TRUE`)
# "Infected" = cites an audited paper, i.e. incorporates its results.
# `labels` maps audited DOI -> display text (default: "Family (Year)").
# Returns the data invisibly so the text can use it, e.g. `r sum(cites$total)`.
# ---------------------------------------------------------------------------
citation_table <- function(csv, labels = NULL, caption = NULL, label = NULL,
                           downstream = TRUE, guidelines = TRUE, note = TRUE) {
  d <- utils::read.csv(csv, stringsAsFactors = FALSE)
  if (!is.null(labels)) {
    hit <- match(d$audited_doi, names(labels))
    d$label[!is.na(hit)] <- labels[hit[!is.na(hit)]]
  }
  show_down  <- isTRUE(downstream) && "reviews_downstream" %in% names(d)
  # Spread to guidelines = guidelines citing the paper directly plus guidelines
  # citing its infected reviews, de-duplicated (citations.py `spread_guidelines`).
  # Older CSVs: fall back to direct + downstream (may double count), or direct only.
  if (!"spread_guidelines" %in% names(d)) {
    d$spread_guidelines <- (if ("guidelines" %in% names(d)) d$guidelines else 0) +
      (if ("downstream_guidelines" %in% names(d)) d$downstream_guidelines else 0)
  }
  show_guide <- isTRUE(guidelines) && ("guidelines" %in% names(d) || "spread_guidelines" %in% names(d))

  # Rows are the audited studies; column heads are kept short and the note
  # under the table spells out what each one counts.
  # Pipe-table column widths follow the dash counts in the alignment row
  # (Pandoc applies them when the table is wider than 72 chars, which it is),
  # so the Study column gets a long run of dashes to keep labels on one line.
  cols <- list(list("Study", d$label, "**Total**", ":----------------------"),
               list("Infected articles", d$total, sum(d$total), ":------:"),
               list("Infected reviews", d$reviews, sum(d$reviews), ":------:"))
  if (show_down)  cols[[length(cols) + 1]] <-
    list("Spread via reviews", d$reviews_downstream, sum(d$reviews_downstream), ":------:")
  if (show_guide) cols[[length(cols) + 1]] <-
    list("Spread to guidelines", d$spread_guidelines, sum(d$spread_guidelines), ":------:")

  head  <- paste0("|", paste(vapply(cols, `[[`, "", 1), collapse = "|"), "|")
  align <- paste0("|", paste(vapply(cols, `[[`, "", 4), collapse = "|"), "|")
  body  <- vapply(seq_len(nrow(d)), function(i)
    paste0("|", paste(vapply(cols, function(cc) as.character(cc[[2]][i]), ""), collapse = "|"), "|"), "")
  total <- paste0("|", paste(vapply(cols, function(cc) {
    v <- cc[[3]]; if (is.numeric(v)) paste0("**", v, "**") else v }, ""), collapse = "|"), "|")
  out <- c(head, align, body, total, "")

  if (!is.null(caption)) {
    out <- c(out, sprintf(": %s {#%s}", caption,
                          if (is.null(label)) "tbl-citations" else label), "")
  }
  if (isTRUE(note)) {
    parts <- c(
      sprintf("Counts are from OpenAlex, retrieved %s, and depend on its coverage; other databases (Scopus, Web of Science, Google Scholar) give different totals.", d$retrieved[1]),
      "A work that cites an audited paper is described here as infected, meaning its findings incorporate that paper's results. *Infected articles* is the number of works indexed by OpenAlex that cite the paper.",
      "*Infected reviews* is the subset of those works that OpenAlex types as a review or whose title indicates a meta-analysis or review.")
    if (show_down) parts <- c(parts,
      "*Spread via reviews* is the total number of citations received by the infected reviews in that row, as a measure of how far the paper's results have propagated; a review that cites more than one audited paper is counted in each row, and a work citing several of those reviews is counted once per review, so rows and the total can overlap.")
    if (show_guide) parts <- c(parts,
      "*Spread to guidelines* is the number of distinct works whose title indicates a clinical guideline, consensus, or position statement and that cite the paper directly or cite one of its infected reviews; only guidelines published in journals are indexed, so policy documents from agencies such as WHO or NICE are not counted, and a guideline reached from more than one audited paper appears in each row.")
    note_text <- paste0("*Note.* ", paste(parts, collapse = " "))
    if (knitr::is_latex_output()) {
      # Pandoc treats the whole \begin..\end block as raw LaTeX, so markdown
      # inside it is not parsed: convert *emphasis* to \emph{} and escape %.
      note_tex <- gsub("\\*([^*]+)\\*", "\\\\emph{\\1}", note_text)
      note_tex <- gsub("%", "\\\\%", note_tex)
      out <- c(out, "\\begin{acetablenote}", note_tex, "\\end{acetablenote}", "")
    } else {
      # HTML: a div styled like the table caption (styles.css .ace-table-note)
      out <- c(out, "::: {.ace-table-note}", note_text, ":::", "")
    }
  }
  cat(out, sep = "\n")
  invisible(d)
}


# ---------------------------------------------------------------------------
# riv_summary_table(): the RIV summary table, generated from the report text
# so it can never disagree with the body. Instances are DECLARED in the text
# by putting the count in front of a RIV reference:
#
#   ... this warrants three instances of 3-@riv-1.7 because ...
#
# The "3-" is stripped from the rendered page (reports/_filters/
# ace-riv-links.lua), so the prose reads normally and can say whatever it
# likes; a later plain @riv-1.7 is only a link and counts nothing. Several
# declarations of the same RIV (for example in different sections) are added
# together. Each row links to the section(s) whose heading carries a
# `{#sec-...}` id above the declaration. Numbers are checked against riv.yml
# (the ACE-RIV taxonomy) and the render stops on an unknown one.
# Use in a chunk with `#| results: asis`:
#
#   riv_summary_table("reports/ACE2026001/index.qmd",
#                     caption = "Summary of Research Integrity Violations identified across the audited studies",
#                     label = "tbl-riv-summary")
#
# Returns the table data invisibly (number, name, instances, section), so the
# text can use e.g. `r sum(riv$instances)` for the total.
# ---------------------------------------------------------------------------
riv_summary_table <- function(qmd, caption = "Summary of Research Integrity Violations",
                              label = "tbl-riv-summary", taxonomy = "riv.yml") {
  txt <- readLines(qmd, warn = FALSE, encoding = "UTF-8")
  # Blank out HTML comments: a RIV named in a commented-out draft, or in the
  # instructions reports/_template/index.qmd carries, is not a finding. Lines
  # are blanked rather than dropped so reported line numbers stay true.
  in_comment <- FALSE
  for (i in seq_along(txt)) {
    line <- txt[i]
    if (in_comment) {
      end <- regexpr("-->", line, fixed = TRUE)
      if (end > 0) { txt[i] <- substring(line, end + 3); in_comment <- FALSE } else txt[i] <- ""
      next
    }
    start <- regexpr("<!--", line, fixed = TRUE)
    if (start > 0) {
      end <- regexpr("-->", line, fixed = TRUE)
      if (end > start) {
        txt[i] <- paste0(substring(line, 1, start - 1), substring(line, end + 3))
      } else {
        txt[i] <- substring(line, 1, start - 1)
        in_comment <- TRUE
      }
    }
  }
  tax <- yaml::read_yaml(taxonomy)
  cats <- do.call(rbind, lapply(tax$sections, function(s)
    do.call(rbind, lapply(s$categories, function(k)
      data.frame(number = k$number, name = k$name, severity = k$severity,
                 stringsAsFactors = FALSE)))))

  pat <- "(?<![0-9A-Za-z])([0-9]+)-@riv-([0-9]+\\.[0-9]+)(?![0-9.]*[0-9])"   # N-@riv-x.y
  decl <- data.frame(number = character(), instances = integer(),
                     section = character(), line = integer(), stringsAsFactors = FALSE)
  section <- NA_character_
  in_code <- FALSE
  for (i in seq_along(txt)) {
    if (grepl("^```", txt[i])) { in_code <- !in_code; next }
    if (in_code) next
    h <- regmatches(txt[i], regexpr("^#+ .*\\{#(sec-[A-Za-z0-9_-]+)\\}", txt[i]))
    if (length(h)) section <- sub(".*\\{#(sec-[A-Za-z0-9_-]+)\\}.*", "\\1", h)
    hits <- regmatches(txt[i], gregexpr(pat, txt[i], perl = TRUE))[[1]]
    for (hit in hits) {
      p <- regmatches(hit, regexec(pat, hit, perl = TRUE))[[1]]
      decl[nrow(decl) + 1, ] <- list(p[3], as.integer(p[2]), section, i)
    }
  }
  if (!nrow(decl)) stop("riv_summary_table: no declarations of the form 'N-@riv-x.y' in ", qmd)

  unknown <- setdiff(decl$number, cats$number)
  if (length(unknown))
    stop("riv_summary_table: not in riv.yml v", tax$version, ": ",
         paste(sprintf("@riv-%s (line %d)", unknown, decl$line[match(unknown, decl$number)]), collapse = ", "))

  nums <- unique(decl$number)
  ord  <- order(as.integer(sub("\\..*", "", nums)), as.integer(sub(".*\\.", "", nums)))
  nums <- nums[ord]
  rows <- vapply(nums, function(n) {
    d <- decl[decl$number == n, ]
    secs <- unique(d$section[!is.na(d$section)])
    sprintf("| **RIV %s** | %s | %d | %s |", n, cats$name[match(n, cats$number)], sum(d$instances),
            if (length(secs)) paste0("@", secs, collapse = ", ") else "")
  }, "")
  total <- sum(decl$instances)
  out <- c("| RIV | Title | Instances | Section |",
           "|:--|:-----------|:-:|:---|",
           rows,
           sprintf("| ***Total*** |  | ***%d*** |  |", total),
           "",
           sprintf(": %s (ACE-RIV v%s) {#%s}", caption, tax$version, label),
           "")
  cat(out, sep = "\n")
  invisible(data.frame(
    number = nums, name = cats$name[match(nums, cats$number)],
    instances = vapply(nums, function(n) sum(decl$instances[decl$number == n]), 1L),
    section = vapply(nums, function(n) paste(unique(na.omit(decl$section[decl$number == n])), collapse = ", "), ""),
    stringsAsFactors = FALSE))
}
