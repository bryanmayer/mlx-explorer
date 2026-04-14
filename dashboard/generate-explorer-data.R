#!/usr/bin/env Rscript
# generate-explorer-data.R
# Discovers Monolix model results and injects data into model-explorer.html
#
# Usage:
#   source("dashboard/generate-explorer-data.R")

library(jsonlite)

# ── Config ──────────────────────────────────────────────────────────────────
# Set BASE_DIR to the parent directory containing your phase subdirectories
# and the model-explorer.html file.
BASE_DIR   <- "."
HTML_FILE  <- file.path(BASE_DIR, "model-explorer.html")
source(file.path(BASE_DIR, "dashboard", "validate-models.R"))

# Keys = exact subdirectory names under BASE_DIR
# Values = display labels shown as phase tabs in the dashboard
# Only directories listed here will be scanned for models.
PHASE_MAP <- list(
  # "directory_name" = "Display Label"    # ← fill in your phase directories
)

# Models to exclude from the dashboard (exact model directory names)
IGNORE_MODELS <- c()

# ── Project-specific plot defaults ────────────────────────────────────────
# LLOQ: lower limit of quantification (on the DATA scale)
# yLimitLower: lower y-axis bound (on the DATA scale)
# dataIsLog: TRUE if the DV is already log10-transformed (e.g., log10 copies/mL)
#            FALSE if the DV is on the natural scale (e.g., copies/mL)
#            When TRUE, LLOQ/yLimitLower are on the log10 scale
# logY: whether to default the log-axis toggle ON in the dashboard
#       (only meaningful when dataIsLog=FALSE; ignored when dataIsLog=TRUE since
#        the data is already logged)
# allowLogToggle: if FALSE, the Log Y checkbox is hidden (use when switching
#                 scales doesn't make sense, e.g., data is already log10)
PLOT_DEFAULTS <- list(
  lloq           = NA,          # e.g. log10(50) for log-scale data, or 50 for natural scale
  yLimitLower    = NA,          # lower y-axis bound on data scale
  dataIsLog      = FALSE,       # TRUE if DV is already log10-transformed
  logY           = FALSE,       # default state of log-axis toggle
  allowLogToggle = TRUE         # show/hide the Log Y checkbox
)

# Parameters that are always fixed by design; omit from "fixed params" notes
NOTES_EXCLUDE <- c()

# ── Helper: safe CSV read ───────────────────────────────────────────────────
safe_read_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
           error = function(e) NULL)
}

# ── Helper: safe key-value read (logLikelihood.txt) ─────────────────────────
read_kv <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  out <- list()
  for (l in lines) {
    parts <- strsplit(l, ",", fixed = TRUE)[[1]]
    if (length(parts) == 2) {
      key <- trimws(parts[1])
      if (nchar(key) == 0) next
      val <- suppressWarnings(as.numeric(parts[2]))
      out[[key]] <- if (is.na(val)) trimws(parts[2]) else val
    }
  }
  out
}

# ── Discover models ─────────────────────────────────────────────────────────
pop_files <- list.files(BASE_DIR, pattern = "^populationParameters\\.txt$",
                        recursive = TRUE, full.names = TRUE)

# Exclude History/ and ModelBuilding/ subdirectories
pop_files <- pop_files[!grepl("/History/", pop_files, fixed = TRUE)]
pop_files <- pop_files[!grepl("/ModelBuilding/", pop_files, fixed = TRUE)]

# Also exclude nested duplicate directories (e.g., decay_effector_freeaE/decay_effector_freeaE/)
# by checking if the parent dir name equals the grandparent dir name AND there's a sibling popParams
pop_files_clean <- character(0)
for (pf in pop_files) {
  model_dir <- dirname(pf)
  dir_name <- basename(model_dir)
  parent_dir <- dirname(model_dir)
  parent_name <- basename(parent_dir)
  # If this is a nested duplicate (dir inside same-named dir), skip it
  if (dir_name == parent_name && file.exists(file.path(parent_dir, "populationParameters.txt"))) {
    next
  }
  pop_files_clean <- c(pop_files_clean, pf)
}
pop_files <- sort(pop_files_clean)

cat(sprintf("Found %d model runs\n", length(pop_files)))

# ── Parse each model ────────────────────────────────────────────────────────
models <- list()
all_warnings <- list()
obs_stored_for_phase <- character(0)  # Track which phases already have obs data

for (pf in pop_files) {
  model_dir <- dirname(pf)
  rel_path  <- sub(paste0(BASE_DIR, "/"), "", model_dir, fixed = TRUE)

  # Determine phase
  phase_key <- sub("/.*", "", rel_path)
  if (nchar(phase_key) == 0) next
  phase     <- PHASE_MAP[[phase_key]] %||% "Unknown"
  if (phase == "Unknown") next

  # Model name: use the innermost directory name
  model_name <- basename(model_dir)

  # Skip ignored models
  if (model_name %in% IGNORE_MODELS) next

  # Model family: second-level directory
  parts <- strsplit(rel_path, "/")[[1]]
  model_family <- if (length(parts) >= 2) parts[2] else model_name

  # ── Population parameters ──
  pop <- safe_read_csv(pf)
  if (is.null(pop)) next

  params <- list()
  for (i in seq_len(nrow(pop))) {
    row <- pop[i, ]
    pname <- trimws(as.character(row$parameter))
    safe_num <- function(x) { if (is.null(x) || length(x) == 0 || identical(x, "")) NA_real_ else suppressWarnings(as.numeric(x)) }
    val   <- safe_num(row[["value"]])
    rse   <- safe_num(row[["rse_sa"]])
    se    <- safe_num(row[["se_sa"]])
    ci_lo <- safe_num(row[["P2.5_sa"]])
    ci_hi <- safe_num(row[["P97.5_sa"]])
    cv    <- safe_num(row[["CV"]])

    # Determine if fixed: truly empty se_sa/rse_sa columns (not "nan")
    # "nan" means Monolix tried to compute SE but failed → parameter was fitted
    raw_rse <- trimws(as.character(row[["rse_sa"]]))
    raw_se  <- trimws(as.character(row[["se_sa"]]))
    is_fixed <- (raw_rse == "" || is.na(raw_rse)) && (raw_se == "" || is.na(raw_se))

    # Classify parameter type
    ptype <- if (grepl("^omega_", pname)) "omega"
    else if (grepl("^corr_", pname)) "correlation"
    else if (pname == "a" || pname == "b") "error"
    else "fixed_effect"

    params[[pname]] <- list(
      name  = pname,
      value = if (is.na(val)) NA else val,
      rse   = if (is.na(rse)) NA else rse,
      se    = if (is.na(se)) NA else se,
      ci_lo = if (is.na(ci_lo)) NA else ci_lo,
      ci_hi = if (is.na(ci_hi)) NA else ci_hi,
      cv    = if (is.na(cv)) NA else cv,
      fixed = is_fixed,
      type  = ptype
    )
  }

  # ── Log-likelihood ──
  ll_path <- file.path(model_dir, "LogLikelihood", "logLikelihood.txt")
  ll <- read_kv(ll_path)

  # ── Shrinkage ──
  shrink_path <- file.path(model_dir, "IndividualParameters", "shrinkage.txt")
  shrink_df   <- safe_read_csv(shrink_path)
  shrinkage   <- list()
  if (!is.null(shrink_df)) {
    for (i in seq_len(nrow(shrink_df))) {
      pname <- trimws(shrink_df$parameters[i])
      smode <- suppressWarnings(as.numeric(shrink_df$shrinkage_mode[i]))
      smean <- suppressWarnings(as.numeric(shrink_df$shrinkage_mean[i]))
      shrinkage[[pname]] <- list(
        name = pname,
        mode = if (is.na(smode)) NA else smode,
        mean = if (is.na(smean)) NA else smean
      )
    }
  }

  # ── Summary info ──
  summary_path <- file.path(model_dir, "summary.txt")
  n_individuals <- NA
  n_observations <- NA
  obs_name <- ""
  if (file.exists(summary_path)) {
    slines <- readLines(summary_path, warn = FALSE)
    for (sl in slines) {
      if (grepl("Number of individuals", sl)) {
        n_individuals <- as.numeric(sub(".*:\\s*", "", sl))
      }
      if (grepl("Number of observations", sl)) {
        m <- regmatches(sl, regexpr("\\d+$", sl))
        if (length(m)) n_observations <- as.numeric(m)
        # Extract observation name
        m2 <- regmatches(sl, regexpr("\\(([^)]+)\\)", sl))
        if (length(m2)) obs_name <- gsub("[()]", "", m2)
      }
    }
  }

  # ── Determine status ──
  has_nan <- any(sapply(params, function(p) is.na(p$value)))
  high_rse <- any(sapply(params, function(p) {
    p$type == "fixed_effect" && !p$fixed && !is.na(p$rse) && p$rse > 50
  }))
  status <- if (has_nan) "failed" else if (high_rse) "warnings" else "converged"

  # ── Count estimated vs fixed ──
  n_estimated <- sum(sapply(params, function(p) !p$fixed))
  n_fixed     <- sum(sapply(params, function(p) p$fixed))

  # Fixed parameter names for notes
  fixed_names <- as.character(unlist(lapply(params, function(p) if (isTRUE(p$fixed)) p$name else NULL)))
  fixed_names <- setdiff(fixed_names, NOTES_EXCLUDE)

  # Flag counts
  n_high_rse <- sum(vapply(params, function(p) {
    p$type == "fixed_effect" && !p$fixed && !is.na(p$rse) && p$rse > 50
  }, logical(1)))
  n_high_shrink <- if (length(shrinkage) == 0) 0L else sum(vapply(shrinkage, function(s) {
    !is.na(s$mode) && s$mode > 40
  }, logical(1)))

  # ── mlxtran file path (for init values) ──
  mlxtran_path <- file.path(dirname(model_dir), paste0(model_name, ".mlxtran"))

  # ── Initial values from .mlxtran file ──
  init_values <- list()
  mlxtran_methods <- list()  # MLE or FIXED per param from .mlxtran
  if (file.exists(mlxtran_path)) {
    mlx_lines <- readLines(mlxtran_path, warn = FALSE)
    in_param_section <- FALSE
    for (ml in mlx_lines) {
      ml <- trimws(ml)
      if (ml == "<PARAMETER>") { in_param_section <- TRUE; next }
      if (grepl("^<", ml) && in_param_section) break  # next section
      if (in_param_section && grepl("=.*value=", ml)) {
        # Parse: "Bt0_pop = {value=0.00006500317, method=MLE}"
        pname <- trimws(sub("\\s*=.*", "", ml))
        val_match <- regmatches(ml, regexpr("value=([^,}]+)", ml))
        if (length(val_match) == 1) {
          val <- suppressWarnings(as.numeric(sub("value=", "", val_match)))
          if (!is.na(val)) init_values[[pname]] <- val
        }
        method_match <- regmatches(ml, regexpr("method=([^,}]+)", ml))
        if (length(method_match) == 1) {
          mlxtran_methods[[pname]] <- sub("method=", "", method_match)
        }
      }
    }
  }

  # Patch is_fixed using mlxtran method as ground truth
  for (pname in names(params)) {
    if (!is.null(mlxtran_methods[[pname]])) {
      params[[pname]]$fixed <- (mlxtran_methods[[pname]] == "FIXED")
    }
  }

  # ── EBE individual parameter modes ──
  ebe_path <- file.path(model_dir, "IndividualParameters", "estimatedIndividualParameters.txt")
  ebe <- list()
  ebe_df <- NULL
  if (file.exists(ebe_path)) {
    ebe_df <- tryCatch(read.csv(ebe_path, stringsAsFactors = FALSE, check.names = FALSE),
                       error = function(e) NULL)
    if (!is.null(ebe_df)) {
      # Find _mode columns (individual parameter modes)
      mode_cols <- grep("_mode$", names(ebe_df), value = TRUE)
      # Only include parameters that have random effects (non-NaN shrinkage)
      re_params <- names(shrinkage)[sapply(shrinkage, function(s) !is.na(s$mode))]
      for (mc in mode_cols) {
        pname <- sub("_mode$", "", mc)
        if (pname %in% re_params) {
          vals <- suppressWarnings(as.numeric(ebe_df[[mc]]))
          vals <- vals[!is.na(vals)]
          if (length(vals) > 0) {
            ebe[[pname]] <- vals
          }
        }
      }
    }
  }

  # ── Individual Fits (curves + observed points) ──
  # Find the fits file — could be y_fits.txt or <obsName>_fits.txt
  charts_dir <- file.path(model_dir, "ChartsData", "IndividualFits")
  indiv_fits <- list()  # list of subject -> list(time, pred) arrays
  indiv_obs  <- list()  # list of subject -> list(time, y, censored)

  if (dir.exists(charts_dir)) {
    fits_files <- list.files(charts_dir, pattern = "_fits\\.txt$", full.names = TRUE)
    obs_files  <- list.files(charts_dir, pattern = "_observations\\.txt$", full.names = TRUE)

    if (length(fits_files) > 0) {
      fits_df <- safe_read_csv(fits_files[1])
      if (!is.null(fits_df)) {
        fits_df$time <- as.numeric(fits_df$time)
        fits_df$indivPredMode <- as.numeric(fits_df$indivPredMode)
        fits_df <- fits_df[!is.na(fits_df$time) & fits_df$time >= 0, ]
        # Downsample: keep every 3rd point per subject to reduce data size
        fits_df <- do.call(rbind, lapply(split(fits_df, fits_df$ID), function(d) {
          idx <- seq(1, nrow(d), by = 3)
          d[idx, ]
        }))
        for (sid in unique(fits_df$ID)) {
          sub <- fits_df[fits_df$ID == sid, ]
          indiv_fits[[as.character(sid)]] <- lapply(seq_len(nrow(sub)), function(i) {
            c(round(sub$time[i], 3), round(sub$indivPredMode[i], 4))
          })
        }
      }
    }

    # Only store observations on the first model per phase to avoid redundancy
    if (length(obs_files) > 0 && !(phase %in% obs_stored_for_phase)) {
      obs_df <- safe_read_csv(obs_files[1])
      if (!is.null(obs_df)) {
        obs_df$time <- as.numeric(obs_df$time)
        # The observation column name varies (y, log10VL, etc.)
        obs_col <- setdiff(names(obs_df), c("ID", "time", "median", "piLower", "piUpper", "censored", "color", "filter"))
        obs_col <- obs_col[1]  # take the first one
        obs_df[[obs_col]] <- as.numeric(obs_df[[obs_col]])
        obs_df$censored <- as.integer(obs_df$censored)
        obs_df <- obs_df[!is.na(obs_df$time) & obs_df$time >= 0, ]
        for (sid in unique(obs_df$ID)) {
          sub <- obs_df[obs_df$ID == sid, ]
          indiv_obs[[as.character(sid)]] <- lapply(seq_len(nrow(sub)), function(i) {
            c(round(sub$time[i], 3), round(sub[[obs_col]][i], 4), sub$censored[i])
          })
        }
        obs_stored_for_phase <- c(obs_stored_for_phase, phase)
      }
    }
  }

  # ── Obs vs Pred diagnostic data ──
  ovp_path <- file.path(model_dir, "ChartsData", "ObservationsVsPredictions",
                        paste0(obs_name, "_obsVsPred.txt"))
  obs_vs_pred <- list()
  if (file.exists(ovp_path)) {
    ovp_df <- safe_read_csv(ovp_path)
    if (!is.null(ovp_df)) {
      # Only uncensored observations
      ovp_df <- ovp_df[ovp_df$censored == 0, ]
      obs_vs_pred <- list(
        id      = as.character(ovp_df$ID),
        y       = as.numeric(ovp_df[[obs_name]]),
        popPred = as.numeric(ovp_df$popPred),
        ipred   = as.numeric(ovp_df$indivPredMode)
      )
    }
  }

  # ── Validate this model ──
  model_warnings <- validate_model(model_dir, model_name, pop, shrink_df, ebe_df)
  if (length(model_warnings) > 0) {
    all_warnings[[length(all_warnings) + 1]] <- list(model = model_name, warnings = model_warnings)
  }

  models[[length(models) + 1]] <- list(
    id             = model_name,
    name           = model_name,
    family         = model_family,
    phase          = phase,
    phase_dir      = phase_key,
    rel_path       = rel_path,
    status         = status,
    params         = params,
    initValues     = init_values,
    likelihood     = ll,
    shrinkage      = shrinkage,
    n_individuals  = n_individuals,
    n_observations = n_observations,
    obs_name       = obs_name,
    n_estimated    = n_estimated,
    n_fixed        = n_fixed,
    fixed_names    = fixed_names,
    n_high_rse     = n_high_rse,
    n_high_shrink  = n_high_shrink,
    ebe            = ebe,
    indivFits      = indiv_fits,
    indivObs       = indiv_obs,
    obsVsPred      = obs_vs_pred
  )
}

cat(sprintf("Parsed %d models across %d phases\n",
            length(models),
            length(unique(sapply(models, `[[`, "phase")))))

# ── Phase-level cross-model validation ────────────────────────────────────
phases <- unique(sapply(models, `[[`, "phase"))
for (ph in phases) {
  ph_models <- Filter(function(m) m$phase == ph, models)
  ph_warnings <- validate_phase(ph_models, ph)
  if (length(ph_warnings) > 0) {
    all_warnings[[length(all_warnings) + 1]] <- list(model = paste0("[Phase: ", ph, "]"), warnings = ph_warnings)
  }
}

# ── Log all validation results ────────────────────────────────────────────
cat("\n\u2500\u2500 Validation \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n")
validation_summary <- list(n_errors = 0L, n_integrity = 0L, n_diagnostic = 0L)
if (length(all_warnings) == 0) {
  cat("  All checks passed.\n")
} else {
  validation_summary <- log_warnings(all_warnings)
}

# ── Per-phase plot settings (from PLOT_DEFAULTS) ─────────────────────────
# All phases share the same defaults; override per-phase here if needed
phase_settings <- list()
for (ph in phases) {
  phase_settings[[ph]] <- list(
    logY           = PLOT_DEFAULTS$logY,
    dataIsLog      = PLOT_DEFAULTS$dataIsLog,
    lloq           = PLOT_DEFAULTS$lloq,
    yLimitLower    = PLOT_DEFAULTS$yLimitLower,
    allowLogToggle = PLOT_DEFAULTS$allowLogToggle
  )
}

# ── Compute staleness metadata ────────────────────────────────────────────
all_pop_mtimes <- file.mtime(pop_files)
max_model_mtime <- max(all_pop_mtimes, na.rm = TRUE)
generated_at    <- Sys.time()

# Build metadata object
meta <- list(
  generatedAt    = format(generated_at, "%Y-%m-%dT%H:%M:%S%z"),
  newestModelAt  = format(max_model_mtime, "%Y-%m-%dT%H:%M:%S%z"),
  nModels        = length(models),
  nIntegrity     = validation_summary$n_integrity,
  nDiagnostic    = validation_summary$n_diagnostic,
  nErrors        = validation_summary$n_errors,
  phaseSettings  = phase_settings
)

# Flatten validation warnings for embedding in HTML (with category)
validation_log <- list()
for (entry in all_warnings) {
  for (w in entry$warnings) {
    validation_log[[length(validation_log) + 1]] <- list(
      model = entry$model, level = w$level, category = w$category, msg = w$msg
    )
  }
}
meta$validationLog <- validation_log

# ── Convert to JSON and inject ──────────────────────────────────────────────
json_str <- toJSON(models, auto_unbox = TRUE, na = "null", pretty = FALSE, digits = NA)
meta_str <- toJSON(meta, auto_unbox = TRUE, na = "null", pretty = FALSE, digits = NA)

html <- readLines(HTML_FILE, warn = FALSE)

start_marker <- "// <!-- MODEL_DATA_START -->"
end_marker   <- "// <!-- MODEL_DATA_END -->"

start_idx <- grep(start_marker, html, fixed = TRUE)
end_idx   <- grep(end_marker, html, fixed = TRUE)

if (length(start_idx) == 0 || length(end_idx) == 0) {
  stop("Could not find MODEL_DATA markers in ", HTML_FILE)
}

injection <- paste0(
  "window.MODEL_DATA = ", json_str, ";\n",
  "window.DASHBOARD_META = ", meta_str, ";"
)

new_html <- c(
  html[1:start_idx],
  injection,
  html[end_idx:length(html)]
)

writeLines(new_html, HTML_FILE)
cat(sprintf("Injected data into %s (%d models)\n", HTML_FILE, length(models)))
