#!/usr/bin/env Rscript
# generate-explorer-figures.R
# Generates EBE box plots and individual fit plots, base64-encodes them,
# and writes analysis/model-figures.js for the Model Explorer dashboard.
#
# Requires: ggplot2, tidyverse, jsonlite, glue, base64enc
# Usage:
#   Rscript R/generate-explorer-figures.R
#   source(root("R", "generate-explorer-figures.R"))

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
  library(glue)
  library(base64enc)
})

root <- rprojroot::find_rstudio_root_file

# ── Project-specific configuration ────────────────────────────────────────────
MODELS_SUBDIR  <- "models"          # must match generate-explorer-data.R
FITS_Y_LABEL   <- "Observed value"  # e.g. "Viral load (log\u2081\u2080 copies/mL)"
# ──────────────────────────────────────────────────────────────────────────────

models_root <- root(MODELS_SUBDIR)

# ── Helpers ────────────────────────────────────────────────────────────────────

plot_to_base64 <- function(p, width = 9, height = 5, dpi = 120) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  ggsave(tmp, plot = p, width = width, height = height, dpi = dpi, bg = "white")
  paste0("data:image/png;base64,", base64encode(tmp))
}

# Parse logNormal parameters from mlxtran (found in History/)
read_lognormal_params <- function(model_dir) {
  mlxtran_files <- list.files(
    model_dir, pattern = "\\.mlxtran$", recursive = TRUE, full.names = TRUE
  ) %>%
    keep(~ !str_detect(.x, "\\.Internals"))

  if (length(mlxtran_files) == 0) return(character(0))

  mlxtran_file <- mlxtran_files[which.max(file.mtime(mlxtran_files))]

  tryCatch({
    lines <- readLines(mlxtran_file, warn = FALSE)
    hits  <- lines[str_detect(lines, "distribution=logNormal")]
    params <- str_match(hits, "^\\s*(\\w+)\\s*=")[, 2]
    params[!is.na(params)]
  }, error = function(e) character(0))
}

# ── EBE box plot ───────────────────────────────────────────────────────────────

make_ebe_plot <- function(model_dir, model_name) {
  path <- file.path(model_dir, "IndividualParameters",
                    "estimatedIndividualParameters.txt")
  if (!file.exists(path)) return(NULL)

  ebe <- tryCatch(
    read_csv(path, col_types = cols(), show_col_types = FALSE),
    error = function(e) NULL
  )
  if (is.null(ebe) || nrow(ebe) == 0) return(NULL)

  mode_cols <- names(ebe) %>% keep(~ str_ends(.x, "_mode"))
  if (length(mode_cols) == 0) return(NULL)

  long <- ebe %>%
    select(id, all_of(mode_cols)) %>%
    pivot_longer(-id, names_to = "param", values_to = "value") %>%
    mutate(param = str_remove(param, "_mode")) %>%
    group_by(param) %>%
    filter(n_distinct(round(value, 6)) > 1) %>%   # skip fixed/constant params
    ungroup()

  if (nrow(long) == 0) return(NULL)

  # Determine which params to show on log10 scale
  lognormal_params <- read_lognormal_params(model_dir)

  log_params <- long %>%
    group_by(param) %>%
    summarise(
      candidate = (param[1] %in% lognormal_params) && all(value > 0, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(candidate) %>%
    pull(param)

  # Pre-transform lognormal params; append "(log₁₀)" to their strip labels
  long <- long %>%
    mutate(
      value_plot  = if_else(param %in% log_params,
                            log10(pmax(value, 1e-12)), value),
      param_label = if_else(param %in% log_params,
                            paste0(param, "\n(log\u2081\u2080)"), param)
    )

  n_params <- n_distinct(long$param_label)
  ncols    <- min(n_params, 4)

  ggplot(long, aes(x = "", y = value_plot)) +
    geom_boxplot(
      fill = "#bfdbfe", color = "#2563eb", alpha = 0.8, width = 0.5,
      outlier.shape = 21, outlier.fill = "#93c5fd", outlier.size = 1.5
    ) +
    geom_jitter(width = 0.15, size = 1.2, alpha = 0.5, color = "#1d4ed8") +
    facet_wrap(~param_label, scales = "free_y", ncol = ncols) +
    labs(
      title = glue("Individual Parameter Distributions (EBE) \u2014 {model_name}"),
      x = NULL, y = "Individual estimate (mode)"
    ) +
    theme_minimal(base_size = 10) +
    theme(
      plot.title       = element_text(size = 11, face = "bold", margin = margin(b = 8)),
      strip.text       = element_text(face = "bold", size = 8),
      axis.text.x      = element_blank(),
      axis.ticks.x     = element_blank(),
      panel.grid.minor = element_blank(),
      panel.spacing    = unit(0.8, "lines")
    )
}

# ── Individual fits plot ───────────────────────────────────────────────────────
# Reads y_fits.txt (dense prediction grid) and y_observations.txt (actual data).

make_fits_plot <- function(model_dir, model_name) {
  fits_path <- file.path(model_dir, "ChartsData", "IndividualFits", "y_fits.txt")
  obs_path  <- file.path(model_dir, "ChartsData", "IndividualFits", "y_observations.txt")

  if (!file.exists(fits_path)) return(NULL)

  fits <- tryCatch(
    read_csv(fits_path, col_types = cols(), show_col_types = FALSE),
    error = function(e) NULL
  )
  if (is.null(fits) || nrow(fits) == 0) return(NULL)

  # Detect column names (Monolix uses camelCase)
  cn <- names(fits)
  id_col   <- cn[tolower(cn) == "id"][1]
  time_col <- cn[tolower(cn) == "time"][1]
  # Prefer indivPredMode, fall back to indivPredMean, then any indivPred*
  pred_col <- {
    candidates <- cn[str_detect(tolower(cn), "indivpredmode|indivpred_mode")]
    if (length(candidates) == 0)
      candidates <- cn[str_detect(tolower(cn), "indivpredmean|indivpred_mean")]
    if (length(candidates) == 0)
      candidates <- cn[str_detect(tolower(cn), "indivpred")]
    candidates[1]
  }

  if (any(is.na(c(id_col, time_col, pred_col)))) return(NULL)

  fits <- fits %>%
    rename(id = !!id_col, time = !!time_col, pred = !!pred_col) %>%
    select(id, time, pred)

  # Read observation points (separate file)
  obs_ready <- NULL
  if (file.exists(obs_path)) {
    obs <- tryCatch(
      read_csv(obs_path, col_types = cols(), show_col_types = FALSE),
      error = function(e) NULL
    )
    if (!is.null(obs) && nrow(obs) > 0) {
      cn_obs   <- names(obs)
      oid      <- cn_obs[tolower(cn_obs) == "id"][1]
      otim     <- cn_obs[tolower(cn_obs) == "time"][1]
      oyv      <- cn_obs[tolower(cn_obs) == "y"][1]
      ocens    <- cn_obs[str_detect(tolower(cn_obs), "cens")][1]

      if (!any(is.na(c(oid, otim, oyv)))) {
        obs_ready <- obs %>%
          rename(id = !!oid, time = !!otim, y = !!oyv)
        if (!is.na(ocens))
          obs_ready <- obs_ready %>% rename(censored = !!ocens)
        else
          obs_ready <- obs_ready %>% mutate(censored = 0L)
        obs_ready <- obs_ready %>% select(id, time, y, censored)
      }
    }
  }

  n_ids      <- n_distinct(fits$id)
  alpha_line <- case_when(n_ids > 20 ~ 0.25, n_ids > 10 ~ 0.4, TRUE ~ 0.6)
  alpha_pt   <- case_when(n_ids > 20 ~ 0.4,  n_ids > 10 ~ 0.55, TRUE ~ 0.75)

  has_cens <- !is.null(obs_ready) &&
    any(obs_ready$censored != 0, na.rm = TRUE)

  p <- ggplot(fits, aes(x = time, group = factor(id))) +
    geom_line(aes(y = pred), color = "#3b82f6", alpha = alpha_line, linewidth = 0.6)

  if (!is.null(obs_ready)) {
    p <- p + geom_point(
      data  = obs_ready %>% filter(censored == 0),
      aes(y = y, group = factor(id)),
      color = "#1e293b", size = 1.2, alpha = alpha_pt, shape = 16
    )
    if (has_cens) {
      p <- p + geom_point(
        data  = obs_ready %>% filter(censored != 0),
        aes(y = y, group = factor(id)),
        color = "#f59e0b", fill = "#fde68a", size = 1.5, alpha = alpha_pt, shape = 25
      )
    }
  }

  subtitle_txt <- paste0(
    "Blue lines = individual predicted (mode)",
    if (!is.null(obs_ready)) "; black = observed" else "",
    if (has_cens) "; \u25bc yellow = below LOD" else "",
    " \u00b7 ", n_ids, " subjects"
  )

  p +
    labs(
      title    = glue("Individual Fits \u2014 {model_name}"),
      subtitle = subtitle_txt,
      x        = "Time",
      y        = FITS_Y_LABEL
    ) +
    theme_minimal(base_size = 10) +
    theme(
      plot.title       = element_text(size = 11, face = "bold"),
      plot.subtitle    = element_text(size = 9, color = "gray50", margin = margin(b = 6)),
      panel.grid.minor = element_blank()
    )
}

# ── Main loop ──────────────────────────────────────────────────────────────────

pop_files <- list.files(
  models_root, pattern = "populationParameters\\.txt",
  recursive = TRUE, full.names = TRUE
) %>%
  keep(~ !str_detect(.x, "/History/"))

if (length(pop_files) == 0) {
  message("No model results found under models/ — no figures generated")
  quit(status = 0)
}

figures <- list()

for (i in seq_along(sort(pop_files))) {
  pop_file   <- sort(pop_files)[i]
  model_dir  <- dirname(pop_file)
  model_name <- basename(model_dir)
  run_id     <- sprintf("run%03d", i)

  message(glue("  [{run_id}] {model_name} ..."))

  ebe_plot <- tryCatch(
    make_ebe_plot(model_dir, model_name),
    error = function(e) { message("    EBE error: ", conditionMessage(e)); NULL }
  )
  fits_plot <- tryCatch(
    make_fits_plot(model_dir, model_name),
    error = function(e) { message("    Fits error: ", conditionMessage(e)); NULL }
  )

  figures[[run_id]] <- list(
    ebe  = if (!is.null(ebe_plot))  plot_to_base64(ebe_plot,  width = 10, height = 4) else NULL,
    fits = if (!is.null(fits_plot)) plot_to_base64(fits_plot, width = 9,  height = 5) else NULL
  )
}

# ── Inject MODEL_FIGURES inline into HTML ─────────────────────────────────────
# Replaces the figures placeholder left by generate-explorer-data.R so the
# HTML remains self-contained and works via file:// without a server.

json_str  <- toJSON(figures, auto_unbox = TRUE, na = "null", pretty = FALSE)
html_path <- root("analysis", "model-explorer.html")

if (file.exists(html_path)) {
  html         <- readLines(html_path, warn = FALSE)
  placeholder  <- which(str_detect(html, "MODEL_FIGURES placeholder"))
  if (length(placeholder) == 1) {
    html[placeholder] <- paste0(
      "  <script>window.MODEL_FIGURES = ", json_str, ";</script>"
    )
    writeLines(html, html_path)
    n <- length(figures)
    message(glue("Injected figures for {n} model(s) inline into model-explorer.html"))
  } else {
    message("Warning: MODEL_FIGURES placeholder not found in model-explorer.html")
  }
} else {
  message("Warning: model-explorer.html not found")
}
