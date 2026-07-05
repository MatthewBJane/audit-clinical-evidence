library(ggplot2)
library(dplyr)
ace_blue   <- "#03e5ff"
ace_purple <- "#e262e2"
ace_axis   <- "#767676"
ace_text   <- "#767676"
ace_blue_dark <- "#02cfe6"
ace_purple_dark <- "#cf50cf"


knitr::opts_chunk$set(
  echo = knitr::is_html_output(),
  warning = FALSE,
  message = FALSE,
  dev = "ragg_png",
  dev.args = list(bg = "transparent"),
  dpi = 300
)



theme_ace <- function(base_size = 12, base_family = "Roboto") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      # Transparent backgrounds
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      legend.background = element_rect(fill = "transparent", color = NA),
      legend.key = element_rect(fill = "transparent", color = NA),
      
      # No grid lines
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      
      # Thin solid axes
      axis.line.x = element_line(color = ace_axis, linewidth = 0.35),
      axis.line.y = element_line(color = ace_axis, linewidth = 0.35),
      axis.ticks = element_line(color = ace_axis, linewidth = 0.35),
      axis.ticks.length = unit(3, "pt"),
      
      # Axis text and titles
      axis.title = element_text(
        family = base_family,
        face = "bold",
        color = ace_text
      ),
      axis.text = element_text(
        family = base_family,
        color = ace_text
      ),
      
      # Plot text
      plot.title = element_text(
        family = base_family,
        face = "bold",
        size = base_size * 1.25,
        color = ace_text,
        margin = margin(b = 6)
      ),
      plot.subtitle = element_text(
        family = base_family,
        size = base_size,
        color = ace_text,
        margin = margin(b = 12)
      ),
      plot.caption = element_text(
        family = "Roboto Mono",
        size = base_size * 0.75,
        color = ace_text,
        hjust = 0,
        margin = margin(t = 10)
      ),
      
      # Legend
      legend.position = "top",
      legend.title = element_blank(),
      legend.text = element_text(
        family = base_family,
        color = ace_text
      ),
      
      # Spacing
      plot.margin = margin(8, 8, 8, 8)
    )
}