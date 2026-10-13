# ---------------------------------------------------------------------------
# ace_tt_pdf(): the HTML table look carried into the PDF. Column labels in grey
# mono; the rules themselves (cyan top rule, grey header and bottom rules) and
# the grey notes are set once for every table in acePDF.tex. The PDF has no
# lines between body rows. Does nothing for HTML, where styles.css does this.
# `n_rows` is unused, kept so existing calls do not change.
ace_tt_pdf <- function(tab, n_rows = NULL) {
  if (!knitr::is_latex_output()) return(tab)
  tinytable::style_tt(tab, i = 0, color = ace_axis, monospace = TRUE, fontsize = 0.85)
}

# The fill behind a failing verdict: translucent in HTML so it reads on the
# dark theme too, solid in the PDF.
ace_no_bg <- function() if (knitr::is_html_output()) "rgba(226, 98, 226, 0.16)" else ace_purple_bg

grimmer_tt <- function(data,
                       mean_col,
                       sd_col,
                       n_col,
                       id_cols = NULL,
                       items = 1,
                       notes = NULL,
                       table = TRUE,
                       yes_color = ace_blue_text,
                       no_color = ace_purple_text,
                       no_bg = NULL,
                       fontsize = 0.9) {
  if (is.null(no_bg)) no_bg <- ace_no_bg()

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
    notes <- paste0(
      if (knitr::is_html_output()) "<i>Note.</i> " else "\\textit{Note.} ",
      sub("^\\s*Note[.:]\\s*", "", notes)
    )
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
  
  # Verdict styling: the failing verdict is bold magenta, the passing verdict a
  # quieter blue at regular weight, so failures are what the eye lands on.
  fill <- function(tab, rows, color, bold, background = NULL) {
    if (!length(rows)) return(tab)
    if (is.null(background)) {
      tinytable::style_tt(tab, i = rows, j = consistent_col, color = color, bold = bold)
    } else {
      tinytable::style_tt(tab, i = rows, j = consistent_col, color = color, bold = bold,
                          background = background)
    }
  }

  tab <- tab |>
    tinytable::style_tt(fontsize = fontsize) |>
    fill(which(out$Consistent == "Yes"), yes_color, FALSE) |>
    fill(which(out$Consistent == "No"), no_color, TRUE, no_bg)
  ace_tt_pdf(tab, nrow(out))
}

# ---------------------------------------------------------------------------
# yesno_tt(): a tinytable with one Yes/No column filled in the ACE colors, the
# same treatment grimmer_tt gives its "Consistent" column. Used for any table
# whose last question is a verdict, so verdict columns look the same wherever
# they appear in a report.
#
#   yesno_tt(df, col = "Reproduces", center = c("Reported", "Recomputed"),
#            notes = "Note. ...")
#
# `col` names the verdict column(s), holding "Yes" or "No"; `center` names any other
# columns to center. Colors default to the same pair grimmer_tt uses.
# ---------------------------------------------------------------------------
yesno_tt <- function(data,
                     col = "Consistent",
                     center = NULL,
                     notes = NULL,
                     class = "ace-grimmer-table",
                     yes_color = ace_blue_text,
                     no_color = ace_purple_text,
                     no_bg = NULL,
                     fontsize = 0.9,
                     groups_i = NULL,
                     width = NULL) {

  # `col` may name more than one verdict column; each is styled the same way.
  # `groups_i` is passed to tinytable::group_tt(i = ) to label blocks of rows.
  stopifnot(all(col %in% names(data)))
  verdict_cols <- which(names(data) %in% col)
  center_cols <- unique(c(which(names(data) %in% center), verdict_cols))

  # House style: a note beginning "Note." / "Note:" gets an italic "Note." label.
  if (!is.null(notes) && is.character(notes)) {
    notes <- paste0(
      if (knitr::is_html_output()) "<i>Note.</i> " else "\\textit{Note.} ",
      sub("^\\s*Note[.:]\\s*", "", notes)
    )
  }

  # `width`: optional column widths as fractions of the table width, passed to tinytable::tt().
  tab <- if (is.null(width)) tinytable::tt(data, notes = notes, class = class) else
    tinytable::tt(data, notes = notes, class = class, width = width)
  if (!is.null(groups_i)) {
    tab <- tab |>
      tinytable::group_tt(i = groups_i) |>
      tinytable::style_tt(i = "groupi", italic = TRUE)
  }
  tab <- tab |>
    tinytable::style_tt(j = seq_along(names(data)), valign = "m") |>
    tinytable::style_tt(j = center_cols, align = "c")

  # Verdict styling: the failing verdict is bold magenta, the passing verdict a
  # quieter blue at regular weight, so failures are what the eye lands on.
  fill <- function(tab, rows, j, color, bold, background = NULL) {
    if (!length(rows)) return(tab)
    if (is.null(background)) {
      tinytable::style_tt(tab, i = rows, j = j, color = color, bold = bold)
    } else {
      tinytable::style_tt(tab, i = rows, j = j, color = color, bold = bold,
                          background = background)
    }
  }

  # Once group_tt(i = ) has inserted label rows, style_tt() row indices refer
  # to the displayed rows, so each data row is pushed down by the number of
  # group rows inserted at or above it.
  shift <- function(rows) {
    if (is.null(groups_i) || !length(rows)) return(rows)
    at <- unlist(groups_i)
    rows + vapply(rows, function(r) sum(at <= r), numeric(1))
  }
  if (is.null(no_bg)) no_bg <- ace_no_bg()
  tab <- tinytable::style_tt(tab, fontsize = fontsize)
  for (j in verdict_cols) {
    tab <- tab |>
      fill(shift(which(data[[j]] == "Yes")), j, yes_color, FALSE) |>
      fill(shift(which(data[[j]] == "No")), j, no_color, TRUE, no_bg)
  }
  ace_tt_pdf(tab, nrow(data) + length(groups_i))
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
      data.frame(number = k$number, name = k$name,
                 stringsAsFactors = FALSE)))))

  pat <- "(?<![0-9A-Za-z])([0-9]+)-@riv-([0-9]+\\.[0-9]+)(?![0-9.]*[0-9])"   # N-@riv-x.y
  decl <- data.frame(number = character(), instances = integer(),
                     section = character(), line = integer(), stringsAsFactors = FALSE)
  # Section numbers as the report displays them: level-2 headings number 1, 2,
  # 3 and level-3 headings letter within them (3.B). The summary table prints
  # these itself rather than using a @sec- cross-reference, which always drags
  # the word "Section" along with it; the prose keeps the prefixed form.
  alpha <- function(n) {
    s <- ""
    while (n > 0) { n <- n - 1L; s <- paste0(LETTERS[(n %% 26) + 1L], s); n <- n %/% 26L }
    s
  }
  secnum <- character()
  major <- 0L
  minor <- 0L

  section <- NA_character_
  in_code <- FALSE
  for (i in seq_along(txt)) {
    if (grepl("^```", txt[i])) { in_code <- !in_code; next }
    if (in_code) next
    lvl <- nchar(regmatches(txt[i], regexpr("^#+(?= )", txt[i], perl = TRUE)))
    if (length(lvl) && lvl %in% 2:3 && !grepl("\\.unnumbered", txt[i])) {
      if (lvl == 2L) { major <- major + 1L; minor <- 0L } else { minor <- minor + 1L }
      num <- if (lvl == 2L) as.character(major) else paste0(major, ".", alpha(minor))
      id <- regmatches(txt[i], regexpr("(?<=\\{#)sec-[A-Za-z0-9_-]+(?=\\})", txt[i], perl = TRUE))
      if (length(id)) secnum[id] <- num
    }
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
  # "3.A" linked to the section, with no prefix word. LaTeX gets \hyperref,
  # which resolves against the \label Quarto writes for a @sec- heading; HTML
  # gets an ordinary anchor link. Falls back to the cross-reference if a
  # section somehow carries no computed number.
  sec_link <- function(id) {
    n <- unname(secnum[id])
    if (is.na(n)) return(paste0("@", id))
    if (knitr::is_latex_output()) sprintf("\\hyperref[%s]{%s}", id, n) else sprintf("[%s](#%s)", n, id)
  }

  rows <- vapply(nums, function(n) {
    d <- decl[decl$number == n, ]
    secs <- unique(d$section[!is.na(d$section)])
    sprintf("| **RIV %s** | %s | %d | %s |", n, cats$name[match(n, cats$number)], sum(d$instances),
            if (length(secs)) paste(vapply(secs, sec_link, ""), collapse = ", ") else "")
  }, "")
  total <- sum(decl$instances)
  out <- c("| RIV | Title | Instances | Section |",
           "|:--|:-----------|:-:|:-:|",
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
