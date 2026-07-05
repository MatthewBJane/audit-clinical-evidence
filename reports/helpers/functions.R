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