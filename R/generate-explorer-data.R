#!/usr/bin/env Rscript
# generate-explorer-data.R
# Auto-discovers saved Monolix model runs under models/ and writes
# analysis/model-data.js for the Model Explorer dashboard.
# Call after any run, or source from the iterative loop.
#
# Usage:
#   Rscript R/generate-explorer-data.R
#   source(root("R", "generate-explorer-data.R"))
#
# ── Project-specific configuration ────────────────────────────────────────────
# Adjust these to match your project layout.

# Directory under project root where Monolix projects are saved.
MODELS_SUBDIR <- "models"

# Named list mapping path prefixes to phase labels.
# First match wins. Set to list() to disable phase inference (phase = "unknown").
PHASE_PATTERNS <- list(
  acute   = "^acute/",
  rebound = "^rebound/"
)

# Parameters to exclude from the auto-generated FIXED notes string.
# List any params that are always fixed by design and don't need annotation.
NOTES_EXCLUDE_PARAMS <- character(0)

# ──────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(glue))

root <- rprojroot::find_rstudio_root_file

# ── Helpers ───────────────────────────────────────────────────────────────────

read_pop_params <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(
    read_csv(path, col_types = cols(), show_col_types = FALSE),
    error = function(e) NULL
  )
}

read_ll <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch({
    # Format: criteria col + one value col (e.g. importanceSampling)
    df <- read_csv(path, col_types = cols(), show_col_types = FALSE)
    val_col <- setdiff(names(df), "criteria")[1]
    vals <- set_names(as.numeric(df[[val_col]]), df$criteria)
    # Use single-bracket indexing so missing keys return NA (not error)
    g <- function(k) { v <- vals[k]; if (is.na(v)) NA_real_ else unname(v) }
    list(
      ll   = g("OFV"),
      aic  = g("AIC"),
      bic  = g("BIC"),
      aicc = g("AICc"),
      bicc = g("BICc")
    )
  }, error = function(e) NULL)
}

read_shrinkage <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(
    read_csv(path, col_types = cols(), show_col_types = FALSE),
    error = function(e) NULL
  )
}

# Derive status from pop params: FAILED > WARNINGS > converged
infer_status <- function(pop) {
  if (is.null(pop)) return("failed")
  if (any(is.nan(pop$value), na.rm = TRUE)) return("failed")
  rse_col <- intersect(names(pop), c("rse_sa", "rse"))[1]
  if (!is.na(rse_col)) {
    high <- pop %>%
      filter(!is.na(.data[[rse_col]]),
             abs(.data[[rse_col]]) > 50,
             !str_detect(parameter, "^omega|^a$"))
    if (nrow(high) > 0) return("warnings")
  }
  "converged"
}

# ── Discover model runs ───────────────────────────────────────────────────────

models_root <- root(MODELS_SUBDIR)

# Find all populationParameters.txt not inside History/
pop_files <- list.files(
  models_root, pattern = "populationParameters\\.txt",
  recursive = TRUE, full.names = TRUE
) %>%
  keep(~ !str_detect(.x, "/History/"))

if (length(pop_files) == 0) {
  message("No model results found under models/")
  quit(status = 0)
}

# ── Build registry + parameter data ──────────────────────────────────────────

registry   <- list()
params_fe  <- list()   # fixed effects
params_re  <- list()   # random effects (omega_*)
params_err <- list()   # error params (a, b, ...)
shrinkage  <- list()

for (pop_file in sort(pop_files)) {
  model_dir  <- dirname(pop_file)
  model_path <- str_remove(model_dir, paste0(models_root, "/"))
  model_name <- basename(model_dir)

  # Infer phase from path using PHASE_PATTERNS config
  phase <- "unknown"
  for (nm in names(PHASE_PATTERNS)) {
    if (str_detect(model_path, PHASE_PATTERNS[[nm]])) { phase <- nm; break }
  }

  # Sequential run_id (padded)
  run_id <- sprintf("run%03d", length(registry) + 1)

  # Timestamps from file mtime
  ts <- format(file.mtime(pop_file), "%Y-%m-%d %H:%M")

  # Read results
  pop <- read_pop_params(pop_file)
  ll  <- read_ll(file.path(model_dir, "LogLikelihood", "logLikelihood.txt"))
  sh  <- read_shrinkage(file.path(model_dir, "IndividualParameters", "shrinkage.txt"))

  status <- infer_status(pop)

  # ── Parse pop params ──────────────────────────────────────────────────────

  rse_col <- if (!is.null(pop)) intersect(names(pop), c("rse_sa", "rse"))[1] else NA

  parse_params <- function(rows) {
    # Guard: rowwise() %>% mutate() on a 0-row tibble evaluates mutate expressions
    # for type inference; .data[[rse_col]] returns numeric(0), causing
    # "argument is of length zero" inside the nested if(). Return empty typed
    # tibble immediately to avoid this.
    if (nrow(rows) == 0)
      return(tibble(name = character(), est = numeric(), rse = numeric(), fixed = logical()))
    rows %>%
      rowwise() %>%
      mutate(
        est   = value,
        rse   = if (!is.na(rse_col) && rse_col %in% names(rows))
                  if (!is.na(.data[[rse_col]])) abs(.data[[rse_col]]) else NA_real_
                else NA_real_,
        fixed = is.na(rse_col) || is.na(if (rse_col %in% names(rows)) .data[[rse_col]] else NA)
      ) %>%
      ungroup() %>%
      select(name = parameter, est, rse, fixed)
  }

  if (!is.null(pop)) {
    fe_rows  <- pop %>% filter(!str_detect(parameter, "^omega"), parameter != "a")
    re_rows  <- pop %>% filter(str_detect(parameter, "^omega"))
    err_rows <- pop %>% filter(parameter == "a")

    params_fe[[run_id]]  <- parse_params(fe_rows)
    params_re[[run_id]]  <- parse_params(re_rows) %>% mutate(fixed = FALSE)
    params_err[[run_id]] <- parse_params(err_rows) %>% mutate(fixed = FALSE)
  }

  # ── Parse shrinkage ───────────────────────────────────────────────────────

  if (!is.null(sh)) {
    sh_clean <- sh %>%
      filter(!is.nan(shrinkage_mean)) %>%
      select(param = parameters, shrinkage = shrinkage_mean)
    # Convert to named list keyed by omega_param
    sh_list <- set_names(as.list(sh_clean$shrinkage),
                         paste0("omega_", sh_clean$param))
    shrinkage[[run_id]] <- sh_list
  }

  # ── Count flags ───────────────────────────────────────────────────────────

  high_rse_count <- 0L
  high_shrink_count <- 0L

  if (!is.null(pop) && !is.na(rse_col)) {
    high_rse_count <- pop %>%
      filter(!str_detect(parameter, "^omega|^a$"),
             !is.na(.data[[rse_col]]),
             abs(.data[[rse_col]]) > 50) %>%
      nrow() %>% as.integer()
  }

  if (!is.null(sh)) {
    high_shrink_count <- sh %>%
      filter(!is.nan(shrinkage_mean), shrinkage_mean > 40) %>%
      nrow() %>% as.integer()
  }

  # ── Derive notes ─────────────────────────────────────────────────────────

  notes_parts <- character(0)
  if (!is.null(pop) && !is.na(rse_col)) {
    fixed_params <- pop %>%
      filter(!str_detect(parameter, "^omega|^a$"),
             is.na(.data[[rse_col]]),
             !parameter %in% NOTES_EXCLUDE_PARAMS) %>%
      pull(parameter)
    if (length(fixed_params) > 0)
      notes_parts <- c(notes_parts,
                       glue("{paste(fixed_params, collapse=', ')} FIXED"))
  }

  registry[[run_id]] <- list(
    run_id              = run_id,
    model_name          = model_name,
    phase               = phase,
    project_path        = model_path,
    timestamp           = ts,
    error_model         = "constant",   # default; extend if stored in summary.txt
    obs_dist            = "normal",
    bic                 = ll$bic  %||% NA_real_,
    aic                 = ll$aic  %||% NA_real_,
    ll                  = ll$ll   %||% NA_real_,
    aicc                = ll$aicc %||% NA_real_,
    bicc                = ll$bicc %||% NA_real_,
    n_est               = if (!is.null(pop))
                            sum(!is.na(if (!is.na(rse_col)) pop[[rse_col]] else rep(NA, nrow(pop))))
                          else NA_integer_,
    n_fixed             = if (!is.null(pop))
                            sum(is.na(if (!is.na(rse_col)) pop[[rse_col]] else rep(NA, nrow(pop))))
                          else NA_integer_,
    status              = status,
    high_rse_count      = high_rse_count,
    high_shrinkage_count = high_shrink_count,
    notes               = if (length(notes_parts)) paste(notes_parts, collapse = "; ") else ""
  )
}

# ── Serialise to JS ───────────────────────────────────────────────────────────

# Convert tibble rows to list-of-lists for JSON
tib_to_records <- function(tib) {
  if (is.null(tib) || nrow(tib) == 0) return(list())
  tib %>%
    mutate(across(where(is.logical), as.integer)) %>%
    pmap(list)
}

js_data <- list(
  registry      = unname(registry),          # array, not named object
  fixedEffects  = map(params_fe,  tib_to_records),
  randomEffects = map(params_re,  tib_to_records),
  errorParams   = map(params_err, tib_to_records),
  shrinkage     = shrinkage
)

json_str <- toJSON(js_data, auto_unbox = TRUE, na = "null", pretty = FALSE)

# ── Inject MODEL_DATA inline into HTML ────────────────────────────────────────
# Inline injection avoids browser file:// restrictions on loading external
# local scripts — the HTML is now fully self-contained.
html_path <- root("analysis", "model-explorer.html")
if (file.exists(html_path)) {
  html <- readLines(html_path, warn = FALSE)
  # Replace everything between the injection markers
  start_idx <- which(str_detect(html, "DATA_INJECTION_START"))
  end_idx   <- which(str_detect(html, "DATA_INJECTION_END"))
  if (length(start_idx) == 1 && length(end_idx) == 1) {
    new_block <- c(
      "  <!-- DATA_INJECTION_START -->",
      glue("  <!-- Generated: {Sys.time()} -->"),
      paste0("  <script>window.MODEL_DATA = ", json_str, ";</script>"),
      "  <!-- MODEL_FIGURES placeholder — replaced by generate-explorer-figures.R -->",
      "  <!-- DATA_INJECTION_END -->"
    )
    html <- c(html[seq_len(start_idx - 1)],
              new_block,
              html[seq.int(end_idx + 1, length(html))])
    writeLines(html, html_path)
    n_models <- length(registry)
    message(glue("Injected {n_models} model(s) inline into model-explorer.html"))
  } else {
    message("Warning: DATA_INJECTION markers not found in model-explorer.html")
  }
}

# Append figures (EBE box plots + individual fits) if the figures script exists
figures_script <- root("R", "generate-explorer-figures.R")
if (file.exists(figures_script)) {
  message("Generating figures...")
  source(figures_script)
}
